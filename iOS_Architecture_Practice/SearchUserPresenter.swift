//
//  SearchUserPresenter.swift
//  RouterSample
//
//  このファイルは “Presenter” を実装している。
//  アーキテクチャとしては MVP（あるいは MVP + Router）に近い構成で、
//  Presenter が次の責務を担う。
//
//  - View からのユーザ操作イベントを受け取り、アプリの振る舞いを決定する（入力）
//  - Model に問い合わせてデータを取得・保持し、View に表示更新を指示する（出力）
//  - 画面遷移が必要なときは Router に依頼する（遷移の意思決定／実行の委譲）
//
//  つまり Presenter は
//    View（UIKitの見た目・イベント） と
//    Model（データ取得・ビジネスロジック） と
//    Router（画面遷移の組み立て・実行）
//  の “間に立つハブ” である。
//
//  Presenter を置く意義:
//  - ViewController に書きがちな「検索」「通信」「状態保持」「画面遷移」を分離できる
//  - ユニットテストしやすい（View/Model/Router をモック化できる）
//  - 画面の振る舞いが Presenter のメソッド群として読み物になる
//

import Foundation
import GitHub

// MARK: - SearchUserPresenterProtocol
//
// View 側（ViewController）が Presenter を使うためのインターフェイス。
// View は “Presenter の実装詳細” を知らず、この protocol 経由でだけ操作するのが理想。
//
// ここでは UITableView 表示に必要な情報（numberOfUsers / user(forRow:)）と、
// ユーザ操作イベント（didSelectRow / didTapSearchButton）を定義している。
protocol SearchUserPresenterProtocol {

    /// 表示対象ユーザ数（TableView の numberOfRows に使う）
    var numberOfUsers: Int { get }

    /// 指定行の User を返す（TableView の cellForRow で使う）
    func user(forRow row: Int) -> User?

    /// 行が選択された（ユーザがタップした）イベント
    func didSelectRow(at indexPath: IndexPath)

    /// 検索ボタンが押されたイベント（SearchBar など）
    func didTapSearchButton(text: String?)
}

// MARK: - SearchUserPresenter
//
// SearchUser 画面の Presenter 実装。
// - 検索結果（users）という画面状態を保持
// - 検索要求が来たら Model に fetch を依頼し、結果に応じて状態更新→View更新
// - 行選択が来たら Router に遷移を依頼する
class SearchUserPresenter: SearchUserPresenterProtocol {

    // MARK: - State

    /// 現在画面に表示するユーザ一覧（検索結果）。
    /// Presenter が保持することで、View は “データを覚える責務” を持たずに済む。
    /// TableView は必要なときに Presenter に問い合わせればよい。
    private(set) var users: [User] = []

    // MARK: - Dependencies

    /// 表示更新を指示する相手（View）。
    /// weak にして循環参照を避ける。
    /// 典型的には ViewController → Presenter を strong に持ち、
    /// Presenter → ViewController は weak にする。
    private weak var view: SearchUserViewProtocol!

    /// データ取得（GitHub API など）を担当する Model。
    /// Presenter は “どうやって取るか” を知らず、protocol 経由で依頼する。
    /// これによりテストで差し替えが容易になる。
    private let model: SearchUserModelProtocol

    /// 画面遷移を担当する Router。
    /// Presenter は “どんな画面を組み立てるか” を知らず、Router に依頼するだけにする。
    private let router: SearchUserRouterProtocol

    // MARK: - Init

    /// 依存注入（DI）で View / Model / Router を受け取って初期化する。
    /// これにより、Presenter 単体テストでは
    /// - MockView
    /// - StubModel
    /// - SpyRouter
    /// を注入して検証できる。
    init(view: SearchUserViewProtocol,
         model: SearchUserModelProtocol,
         router: SearchUserRouterProtocol) {
        self.view = view
        self.model = model
        self.router = router
    }

    // MARK: - Output for View (TableView data source)

    /// 表示するユーザ数。
    /// ViewController はここを numberOfRowsInSection に使う想定。
    var numberOfUsers: Int {
        return users.count
    }

    /// 指定行のユーザを返す。
    ///
    /// アルゴリズム:
    /// 1) row が配列範囲内かチェック
    /// 2) 範囲外なら nil
    /// 3) 範囲内なら users[row]
    ///
    /// こうしておくことで、View 側が index out of range で落ちにくくなる。
    func user(forRow row: Int) -> User? {
        guard row < users.count else { return nil }
        return users[row]
    }

    // MARK: - Input from View (User Actions)

    /// 行選択イベント。
    ///
    /// アルゴリズム:
    /// 1) indexPath.row から対象 User を取り出す
    /// 2) User が取れたら login（ユーザ名）を Router に渡して遷移を依頼する
    ///
    /// ここで Presenter が直接 push/present しないのがポイント。
    /// 遷移の組み立てと実行は Router 側に閉じ込めることで、
    /// Presenter は “遷移したい” という意思だけを表現する。
    func didSelectRow(at indexPath: IndexPath) {
        guard let user = user(forRow: indexPath.row) else { return }
        router.transitionToUserDetail(userName: user.login)
    }

    /// 検索ボタンイベント。
    ///
    /// アルゴリズム（検索処理の流れ）:
    /// 1) text を query として取り出す（nil なら何もしない）
    /// 2) 空文字なら何もしない（無駄なAPIリクエストを防ぐ）
    /// 3) Model に fetchUser を依頼（非同期）
    /// 4) 成功:
    ///      - Presenter の状態 users を更新
    ///      - メインスレッドで View に reload を指示
    ///    失敗:
    ///      - TODO（エラー表示など）
    ///
    /// なぜ DispatchQueue.main.async が必要か:
    /// - fetchUser の completion はバックグラウンドスレッドで返る可能性がある
    /// - UIKit の更新（tableView.reloadData 等）はメインスレッドで行う必要がある
    func didTapSearchButton(text: String?) {
        guard let query = text else { return }
        guard !query.isEmpty else { return }

        model.fetchUser(query: query) { [weak self] result in
            // weak self にしているのは、通信中に画面が閉じられたとき
            // Presenter が解放されてもコールバックが残り続ける事故を避けるため。
            // self が nil なら以降は何もしない。

            switch result {
            case .success(let users):
                // (成功) 検索結果で Presenter の状態を更新
                self?.users = users

                // (成功) UI更新はメインスレッドで
                DispatchQueue.main.async {
                    self?.view.reloadTableView()
                }

            case .failure:
                // (失敗) 現状は何もしない（TODO）
                // 実務ではここで:
                // - エラーメッセージ表示
                // - リトライ導線
                // - ローディング解除
                // などを View に指示する。
                ()
            }
        }
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) ローディング状態の導入
//    - 検索開始 → loading 表示
//    - 完了 → loading 非表示
//    を Presenter が View に通知すると UX が良くなる。
//
// 2) エラーハンドリングを具体化
//    - ネットワークエラー / API制限 / 0件
//    などを区別し、View に表示メッセージを渡す設計が定番。
//
// 3) 入力の正規化
//    - 前後空白を trim
//    - 連続検索のデバウンス
//    - 同一クエリの二重発火抑止
//
// 4) スレッドの取り扱い方針
//    - Model が “必ずメインで返す” 契約にするなら Presenter 側の main.async は不要になる。
//    - ただし契約が曖昧だと UI 更新の安全性が崩れるため、どこで保証するかを統一する。
//
// 5) View を weak implicitly unwrapped (!) にしている点
//    - view が nil になると何も更新されない。
//    - init 時に必須なら non-optional にする、または debug で落とす方針もあり得る。
//```