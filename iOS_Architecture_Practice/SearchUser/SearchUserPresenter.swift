//
//  SearchUserPresenter.swift
//  MVPSample
//
//  このファイルは MVP (Model-View-Presenter) における Presenter を実装している。
//  Presenter は「画面の意思決定」と「状態管理」と「View への出力」を担当し、UIKit 依存を最小化するのが狙いである。
//
//  ここでの主要なアルゴリズムは次の2本。
//  (1) 検索アルゴリズム（検索ボタン押下 → API取得 → 内部状態更新 → View更新）
//  (2) 遷移アルゴリズム（行選択 → 選択User特定 → Viewへ遷移命令）
//
//  ViewController（View）は、UIイベントを Presenter に渡すだけ。
//  Model はデータ取得（GitHub API 等）を担当。
//  Presenter は、それらを繋ぎ「画面として成立する一連の流れ」を組み立てる役である。
//

import Foundation
import GitHub

// MARK: - Presenter Input (View -> Presenter)
//
// View（SearchUserViewController）側が Presenter を操作するための入口プロトコル。
// View が Presenter の具象型に依存しないようにする（テスト容易性・差し替え容易性）。
//
// アルゴリズム的には:
// - numberOfUsers / user(forRow:) は “描画に必要なデータ提供API”
// - didSelectRow / didTapSearchButton は “UIイベント入力API”
// である。
protocol SearchUserPresenterInput {

    /// TableView の行数決定に使う。
    /// View は users 配列を持たず、Presenter の状態に問い合わせて UI を組み立てる。
    var numberOfUsers: Int { get }

    /// indexPath.row に対応する User を返す。
    /// View は表示用データを Presenter に問い合わせるだけで良い。
    func user(forRow row: Int) -> User?

    /// TableView の行選択イベントを Presenter に通知する。
    /// 選択に対する意思決定（遷移する/しない、どこに行くか）は Presenter が持つ。
    func didSelectRow(at indexPath: IndexPath)

    /// 検索ボタン押下イベントを Presenter に通知する。
    /// 入力バリデーションや検索実行の起点は Presenter が持つ（View は受け流す）。
    func didTapSearchButton(text: String?)
}

// MARK: - Presenter Output (Presenter -> View)
//
// Presenter が View に対して「やってほしいこと」を依頼するための出口プロトコル。
// Presenter は UIKit を直接触らず、このプロトコル越しに View を操作する。
// これにより Presenter を純粋ロジックとしてテストしやすくできる。
protocol SearchUserPresenterOutput: AnyObject {

    /// 検索結果が更新されたことを View に通知する。
    /// View はテーブルを再描画する（reloadData 等）。
    func updateUsers(_ users: [User])

    /// ユーザ詳細画面へ遷移してほしいことを View に通知する。
    /// “遷移の意思決定” は Presenter、 “UIKit の実行” は View という分担。
    func transitionToUserDetail(userName: String)
}

// MARK: - Presenter Implementation
//
// Presenter は View と Model の間で、画面のアルゴリズム（入力→状態→出力）を担当する。
// 具体的には:
// - users を内部状態として保持し、View の DataSource 要求に応える
// - 検索入力を検証し、Model へ fetch を依頼し、結果を users に反映し、View を更新する
// - 行選択時に users から対象を特定し、View に遷移命令を出す
final class SearchUserPresenter: SearchUserPresenterInput {

    // MARK: - State (Presenter-owned)

    /// 検索結果の内部状態。
    /// MVP では「表示に必要な状態」は Presenter が保持することが多い。
    /// View はこの状態を直接持たず、必要なときに Presenter の API を叩く。
    private(set) var users: [User] = []

    // MARK: - Dependencies

    /// 出力先の View。
    /// weak なのは循環参照回避のため。
    ///
    /// - ViewController は通常 Presenter を strong で保持する
    /// - Presenter が View を strong で保持すると ViewController <-> Presenter で循環参照になる
    /// ため、Presenter 側を weak にするのが定石。
    ///
    /// ここは IUO(!) になっているので init 時に必ず注入される前提。
    private weak var view: SearchUserPresenterOutput!

    /// データ取得を担当する Model。
    /// “どこからデータを取るか（API/DB/Cache）” を Presenter から切り離すためにプロトコルで受ける。
    private var model: SearchUserModelInput

    // MARK: - Init (Dependency Injection)

    /// Presenter は init で依存を注入する（DI）。
    /// これによりテストではモック Model / モック View を差し替えられる。
    init(view: SearchUserPresenterOutput, model: SearchUserModelInput) {
        self.view = view
        self.model = model
    }

    // MARK: - DataSource APIs (View -> Presenter)

    /// View が TableView の行数を決めるための API。
    var numberOfUsers: Int {
        return users.count
    }

    /// row に対応する User を返す。
    /// 範囲外アクセスをガードして nil を返すことで、View 側は安全に扱える。
    func user(forRow row: Int) -> User? {
        guard row < users.count else { return nil }
        return users[row]
    }

    // MARK: - Event Handling Algorithms (UI Input)

    /// 行選択イベント処理。
    /// アルゴリズム:
    /// 1) indexPath.row から選択された User を特定
    /// 2) user.login を使って遷移先の識別子（userName）を決める
    /// 3) View に遷移命令を出す（UIKit処理は View が行う）
    func didSelectRow(at indexPath: IndexPath) {
        guard let user = user(forRow: indexPath.row) else { return }
        view.transitionToUserDetail(userName: user.login)
    }

    /// 検索ボタン押下イベント処理。
    ///
    /// アルゴリズム（重要）:
    /// 1) 入力テキストを検証（nil/空文字の排除）
    /// 2) Model にデータ取得を依頼（非同期）
    /// 3) 結果に応じて Presenter 内部状態 users を更新
    /// 4) View を更新（UIスレッドで）
    ///
    /// ここで Presenter は「検索開始から画面更新までの一連の流れ」を支配しており、
    /// これが MVP における Presenter の中核責務である。
    func didTapSearchButton(text: String?) {

        // --- 1) 入力バリデーション ---
        // text が nil なら検索できないので終了。
        guard let query = text else { return }

        // 空文字なら検索しない（無駄なAPIコール防止）。
        // ここで trim（前後空白除去）したい場合もある。
        guard !query.isEmpty else { return }

        // --- 2) Model に検索を依頼（非同期） ---
        // Model は GitHub API など実データ取得を担当する想定。
        // completion は非同期で呼ばれる可能性が高い。
        model.fetchUser(query: query) { [weak self] result in

            // weak self なのは、検索中に画面が閉じられた場合に Presenter が解放されても
            // completion が生き残る可能性があるため。
            // unowned にすると解放後に呼ばれた瞬間クラッシュする。
            switch result {

            case .success(let users):

                // --- 3) Presenter の内部状態を更新 ---
                // “表示状態のソースオブトゥルース” を Presenter が持つ構造なので、ここで users を差し替える。
                self?.users = users

                // --- 4) View を更新（必ずメインスレッド） ---
                // Model の completion がどのスレッドで返ってくるかは保証されないため、
                // UIKit を触る処理は main にディスパッチする。
                DispatchQueue.main.async {
                    // Output プロトコル越しに View へ命令を出す。
                    // View 側は reloadData を呼び、DataSource 経由で Presenter の users を参照して描画する。
                    self?.view.updateUsers(users)
                }

            case .failure(let error):

                // エラー時の扱いは未実装（TODO）。
                // MVP的には Presenter がエラー種別を解釈して
                // - View にアラート表示命令
                // - リトライUI表示
                // - 空状態表示
                // 等を出すのが自然。
                //
                // 現状は print のみで、ユーザ体験としては弱い。
                print(error)
                ()
            }
        }
    }
}