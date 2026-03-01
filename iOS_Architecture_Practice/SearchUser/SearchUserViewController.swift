//
//  SearchUserViewController.swift
//  MVPSample
//
//
//  このファイルは MVP (Model-View-Presenter) の "View" に相当する ViewController 実装である。
//  UIKit の都合で UIViewController を継承しているが、アーキテクチャ的には「View層」の責務に寄せている。
//  具体的には、次の方針が読み取れる:
//
//  - ViewController は UI イベントを受ける（UISearchBar / UITableView の delegate）
//  - 受けたイベントを Presenter に 전달する（didTapSearchButton / didSelectRow）
//  - 表示に必要なデータは Presenter から取得する（numberOfUsers / user(forRow:)）
//  - 画面遷移のトリガも Presenter から View(Output) に通知される（transitionToUserDetail）
//
//  つまり ViewController は「入力（UIイベント）→ Presenter」「出力（画面更新/遷移）← Presenter」
//  の “I/Oアダプタ” として振る舞うのが狙いである。
//  Cocoa MVC と違って、ViewController が Model を直接触らない点がポイントである。
//

import UIKit
import GitHub

// MARK: - View (MVP)
// final にしているのは、継承で振る舞いが変化する余地を減らし、意図を固定するため。
// MVPでは View と Presenter の接続関係が重要なので、継承で壊れにくい形が好まれる。
final class SearchUserViewController: UIViewController {

    // MARK: UI Outlets

    /// ユーザ検索用の検索バー（Storyboard/XIB から接続される）
    /// View は UI パーツの所有者である。
    @IBOutlet private weak var searchBar: UISearchBar!

    /// 検索結果を表示するテーブルビュー
    @IBOutlet private weak var tableView: UITableView!

    // MARK: Presenter (View -> Presenter)

    /// Presenter への参照。
    /// MVP において View は Presenter に依存し、Presenter が画面ロジックを持つ。
    ///
    /// ここでは暗黙アンラップ（!）になっているため、
    /// inject が呼ばれずに参照するとクラッシュする。
    /// つまり「DIが前提」という設計である。
    ///
    /// 実用では
    /// - viewDidLoad 前に必ず inject される保証
    /// - または optional + guard で防御
    /// を明確にすることが多い。
    private var presenter: SearchUserPresenterInput!

    /// DI（Dependency Injection）用のメソッド。
    /// Storyboard 生成だと init で注入しにくいので、後注入する形にしている。
    /// Composition Root（組み立て側）がこのメソッドを呼び出して接続を完成させる。
    func inject(presenter: SearchUserPresenterInput) {
        self.presenter = presenter
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // View の初期セットアップ。
        // MVP の基本として、ここでは “UI設定” に留め、
        // データ取得や状態管理は Presenter 側に寄せるのがセオリー。
        setup()
    }

    // MARK: Setup (UI only)

    /// テーブルの見た目とセル登録を行う。
    /// ここは純粋な UI 設定であり、Presenter ロジックを含めない点が MVP 的に良い。
    private func setup() {
        // estimatedRowHeight を設定することで AutoLayout による動的セル高さ計算のパフォーマンスが改善する。
        tableView.estimatedRowHeight = 64

        // self-sizing cell を有効化。cell 内の AutoLayout で高さが決まる。
        tableView.rowHeight = UITableView.automaticDimension

        // Nib からセルを登録。Storyboard で prototype cell を使わず、セルを独立させている。
        // これによりセルの再利用・テスト・分離がしやすい。
        tableView.register(UINib(nibName: "UserCell", bundle: nil),
                           forCellReuseIdentifier: "UserCell")
    }
}

// MARK: - UISearchBarDelegate (View: Input)
//
// ユーザが検索バーで検索を実行した時の “入力イベント” を受ける。
// View はこのイベントを Presenter に渡すだけにする。
extension SearchUserViewController: UISearchBarDelegate {

    /// キーボードの検索ボタンが押されたときに呼ばれる。
    /// Cocoa MVC だとここで API 呼び出し等を始めがちだが、MVP では Presenter に委譲する。
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // View -> Presenter へのイベント通知。
        // text は Optional(String?) なので、Presenter 側で nil/空文字を含めたバリデーションを行う設計が自然。
        presenter.didTapSearchButton(text: searchBar.text)
    }
}

// MARK: - UITableViewDelegate (View: Input)
//
// 行選択などの UI 入力イベントを Presenter に渡す。
extension SearchUserViewController: UITableViewDelegate {

    /// 行がタップされた時に呼ばれる。
    /// View は UI の反応（deselect）だけをして、意思決定は Presenter に委譲する。
    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {
        // UI 的には選択状態を解除しておく（見た目上のフィードバック）
        tableView.deselectRow(at: indexPath, animated: true)

        // View -> Presenter : 「どの行が選択されたか」を伝える
        presenter.didSelectRow(at: indexPath)
    }
}

// MARK: - UITableViewDataSource (View: Output adapter)
//
// テーブルビューが表示に必要なデータを要求してくる。
// MVP では View がデータを保持せず、Presenter を “データ提供者” として利用することが多い。
// ここでも presenter.numberOfUsers / presenter.user(forRow:) で供給している。
extension SearchUserViewController: UITableViewDataSource {

    /// セクション内の行数は Presenter が持つ状態（検索結果数）に基づく。
    /// View は状態を持たず、Presenter の状態を参照して UI を構成する。
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        return presenter.numberOfUsers
    }

    /// 各行のセル生成。
    /// 表示に必要な User データは Presenter から取得し、セルに渡して描画する。
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        // Reuse Identifier を使ってセルを再利用する。
        // as! は “UserCell が必ず返る” 前提。登録ミスがあるとクラッシュするため、
        // 実務では guard let で安全にする場合もある。
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell") as! UserCell

        // Presenter から行に対応するユーザを取得する。
        // Optional になっているため、Presenter 側で範囲外アクセスを避ける/データ未取得を表す等の設計が可能。
        if let user = presenter.user(forRow: indexPath.row) {
            // セルの描画はセル自身に委譲し、ViewController は「データを渡す」だけにする。
            // これも責務分離（ViewController の肥大化防止）に効く。
            cell.configure(user: user)
        }

        return cell
    }
}

// MARK: - SearchUserPresenterOutput (Presenter -> View)
//
// Presenter が View を更新したいときに呼ぶ出力インターフェース。
// ここが “View の API” であり、Presenter はこのプロトコル越しに View を操作する。
// そのため Presenter は UIKit 依存を最小限にでき、テストがしやすくなる。
extension SearchUserViewController: SearchUserPresenterOutput {

    /// 検索結果が更新された時に呼ばれる想定。
    /// 引数 users を受け取っているが、現状は使っていない（Presenter が内部保持している設計）。
    /// つまり View は「再描画命令」を受けるだけで、データ本体は Presenter から DataSource 経由で引く。
    ///
    /// これは MVP でよくある “Presenter が状態を保持” するパターンである。
    /// 改善余地としては、users を View 側に渡して描画する方式（Viewが表示状態を持つ）もあり得る。
    func updateUsers(_ users: [User]) {
        tableView.reloadData()
    }

    /// ユーザ詳細画面へ遷移する。
    /// MVP の論点として「遷移は誰が担当するか」がある。
    ///
    /// この実装では：
    /// - Presenter が「遷移してほしい」という意思決定を行い
    /// - View が UIKit の具体的遷移操作（Storyboard生成、push）を実行する
    ///
    /// という分担になっている。
    /// これにより Presenter は UIKit の生成/遷移 API を直接叩かずに済む（依存を薄める）。
    ///
    /// ただし、View が次画面の Presenter/Model の組み立てまで行っており、
    /// 「Composition Root が View に入り込んでいる」点は賛否が分かれる。
    /// 大規模では Router/Coordinator/Assembler などに分離するのが一般的。
    func transitionToUserDetail(userName: String) {

        // Storyboard から UserDetail 画面を生成。
        // instantiateInitialViewController() を使っているため、
        // Storyboard 側で Initial VC が正しく設定されている前提。
        let userDetailVC = UIStoryboard(
            name: "UserDetail",
            bundle: nil
        ).instantiateInitialViewController() as! UserDetailViewController

        // 次画面の Model を生成。
        // ここでの Model は “画面モデル” であり、ドメインモデルとは別物の可能性がある。
        let model = UserDetailModel(userName: userName)

        // 次画面の Presenter を生成し、View と Model を結線する。
        // ここは “MVPの組み立て” に相当し、理想的には Composition Root（Assembler）に寄せたい。
        let presenter = UserDetailPresenter(
            userName: userName,
            view: userDetailVC,
            model: model
        )

        // ViewController は inject で Presenter を受け取り、接続を完成させる。
        userDetailVC.inject(presenter: presenter)

        // 画面遷移自体は UIKit の責務なので View が実行するのは自然。
        navigationController?.pushViewController(userDetailVC, animated: true)
    }
}