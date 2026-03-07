//
//  SearchUsersViewControllerTests.swift
//  FluxWithRxSwiftTests
//
//
//  このファイルは、Flux + RxSwift 構成における
//  RepositorySearchViewController の振る舞いをテストする XCTest である。
//
//  ここでのテスト対象は ViewController そのものだが、
//  実際に検証しているのは「画面の見た目」だけではなく、
//  次の 2 つのアルゴリズムである。
//
//  1. ユーザ操作（検索ボタン押下）が ActionCreator → API 呼び出しへ正しく伝わるか
//  2. Store の状態変化が ViewController の UI（TableView）に正しく反映されるか
//
//  つまりこのテストは、ViewController を起点にした
//
//      UI Event → ActionCreator → Dispatcher / Store → UI Reflection
//
//  という一連のフローを確認している。
//
//  全体像を図にすると次の通りである。
//
// -------------------------------------------------------------
//                 User Event / Test Event
//                      │
//                      ▼
//      RepositorySearchViewController
//                      │
//                      ▼
//                ActionCreator
//                      │
//          ┌───────────┼───────────┐
//          │                           │
//      API 通信                    Store 更新
//          │                           │
//          ▼                           ▼
// MockGitHubApiSession      SearchRepositoryStore
//          │                           │
//          ▼                           ▼
//     Param Observable         repositoriesObservable
//          │                           │
//          └───────────┬───────────┘
//                      │
//                      ▼
//                  Test Assertion
// -------------------------------------------------------------
//
//  このテストの良い点は、
//  本物の API 通信や本物の永続化に依存せず、
//  Mock / Test Dispatcher / Test Store を使って
//  ViewController の振る舞いをかなり高い粒度で検証している点である.
//

import XCTest
import GitHub
@testable import FluxWithRxSwift

// MARK: - SearchUsersViewControllerTests
//
// 名前は SearchUsersViewControllerTests だが、実際にテストしているのは
// RepositorySearchViewController である。
// これはサンプルコードの命名由来で残っている可能性が高い。
//
// このテストクラスでは、各テストケースごとに
// - 独立した Dispatcher
// - Mock API
// - Mock LocalCache
// - Store
// - ViewController
// を組み立てることで、テスト同士の状態汚染を防いでいる。
final class SearchUsersViewControllerTests: XCTestCase {

    // MARK: - Dependency Container
    //
    // テスト対象を構成する依存をひとまとめにした構造体。
    //
    // ViewController は本来、アプリ本体では shared な Dispatcher / Store を使う可能性があるが、
    // テストではそれを使うと状態が共有されてしまい、
    // テスト同士が干渉する危険がある。
    //
    // そのため、ここでは各テスト専用の依存を手作業で組み立てている。
    //
    // 構造は次の通り。
    //
    // -------------------------------------------------------------
    //                    Dependency
    //                        │
    //        ┌───────────────┼───────────────┐
    //        │                               │
    //        ▼                               ▼
    // MockGitHubApiSession              MockLocalCache
    //        │
    //        ▼
    //     Dispatcher
    //        │
    //        ├───────────────┬────────────────┐
    //        │               │                │
    //        ▼               ▼                ▼
    //  ActionCreator   SearchRepositoryStore  SelectedRepositoryStore
    //        │               │                │
    //        └───────────────┴────────────────┘
    //                        │
    //                        ▼
    //        RepositorySearchViewController
    // -------------------------------------------------------------
    //
    // このように ViewController を実行するのに必要な最小限の本物 / モックを注入している。
    private struct Dependency {

        /// GitHub API のモック実装。
        ///
        /// 検索が呼ばれたときの query / page を監視できる。
        /// また、テスト側から任意の Repository 結果を流し込める。
        let apiSession = MockGitHubApiSession()

        /// ローカルキャッシュのモック。
        ///
        /// このテストでは favorites を直接検証していないが、
        /// ActionCreator の初期化に必要なため注入している。
        let localCache = MockLocalCache()

        /// 各テスト専用の Dispatcher。
        ///
        /// shared を使わず新規生成することで、
        /// 他テストや他の Store とイベントが混線しないようにする。
        let dispatcher = Dispatcher()

        /// テスト対象の ViewController。
        let viewController: RepositorySearchViewController

        // Dependency の初期化。
        //
        // アルゴリズム:
        // 1. ActionCreator をテスト用依存で作る
        // 2. Store も同じ Dispatcher に紐づけて作る
        // 3. それらを ViewController に注入する
        // 4. loadViewIfNeeded() で viewDidLoad まで進め、UI / 購読を準備する
        //
        // 最後の loadViewIfNeeded() が重要で、
        // これを呼ばないと IBOutlet がまだ接続されず、
        // searchBar や tableView をテストで触れない。
        init() {
            let actionCreator = ActionCreator(dispatcher: dispatcher,
                                              apiSession: apiSession,
                                              localCache: localCache)

            let searchRepositoryStore = SearchRepositoryStore(dispatcher: dispatcher)
            let selectedRepositoryStore = SelectedRepositoryStore(dispatcher: dispatcher)

            self.viewController = RepositorySearchViewController(
                actionCreator: actionCreator,
                searchRepositoryStore: searchRepositoryStore,
                selectedRepositoryStore: selectedRepositoryStore
            )

            // View をロードし、IBOutlet 接続・viewDidLoad 実行・Rx 購読設定を完了させる。
            viewController.loadViewIfNeeded()
        }
    }

    /// 各テストケースで使う依存コンテナ。
    private var dependency: Dependency!

    // MARK: - Setup
    //
    // 各テストの前に呼ばれる。
    // 毎回新しい Dependency を作ることで、テストの独立性を確保する。
    override func setUp() {
        super.setUp()

        dependency = Dependency()
    }

    // MARK: - testSearchButtonClicked
    //
    // このテストは「検索ボタン押下が API 呼び出しまで正しく届くか」を検証する。
    //
    // ここで確認したいアルゴリズムは次の通りである。
    //
    // -------------------------------------------------------------
    // SearchBar に query を入力
    //        │
    //        ▼
    // searchButtonClicked
    //        │
    //        ▼
    // RepositorySearchViewController
    //        │
    //        ▼
    // ActionCreator.searchRepositories(query:)
    //        │
    //        ▼
    // MockGitHubApiSession.searchRepositories(query:page:)
    //        │
    //        ▼
    // searchRepositoriesParams Observable
    //        │
    //        ▼
    // Test Assertion
    // -------------------------------------------------------------
    //
    // つまり ViewController の UI イベント処理が
    // ActionCreator → API Session に正しく接続されているかを見るテストである。
    func testSearchButtonClicked() {

        // テスト用の検索文字列。
        let query = "username"

        // API が呼ばれたことを待つための expectation。
        let expect = expectation(description: "waiting called apiSession.searchRepositories")

        // Mock API の “検索呼び出しパラメータ” を監視する。
        //
        // この Observable には
        //   (query, page)
        // が流れてくる。
        //
        // ここで確認したいことは次の 2 点である。
        // - query が SearchBar に入れた文字列と一致するか
        // - page が初回検索として 1 になっているか
        let disposable = dependency.apiSession.searchRepositoriesParams
            .subscribe(onNext: { _query, _page in
                XCTAssertEqual(_query, query)
                XCTAssertEqual(_page, 1)
                expect.fulfill()
            })

        // ViewController の SearchBar を取得。
        let searchBar = dependency.viewController.searchBar!

        // 文字列を直接設定する。
        searchBar.text = query

        // UISearchBarDelegate の textDidChange を手動で呼んでいる。
        //
        // 実際のアプリではユーザ入力により delegate / Rx イベントが発火するが、
        // テストでは UI の実際のタップや入力を再現しないため、
        // 必要な delegate メソッドを明示的に起動して流れを進める。
        //
        // ただしこの ViewController は textDidChange 自体を明示的に使っていないので、
        // ここは “入力イベントを少し現実に近づける” ための補助的呼び出しと考えられる。
        searchBar.delegate!.searchBar!(searchBar, textDidChange: query)

        // 検索ボタン押下イベントを手動で発火させる。
        //
        // これにより、ViewController 側の
        //   searchBar.rx.searchButtonClicked
        // の購読処理が動き、ActionCreator.searchRepositories(query:) が呼ばれる。
        searchBar.delegate!.searchBarSearchButtonClicked!(searchBar)

        // API 呼び出しが行われるまで待つ。
        wait(for: [expect], timeout: 1)

        // 購読解除。
        disposable.dispose()
    }

    // MARK: - testReloadData
    //
    // このテストは「Store の検索結果更新が TableView の表示に反映されるか」を検証する。
    //
    // 見たいアルゴリズムは次の通りである。
    //
    // -------------------------------------------------------------
    // dispatch(.searchRepositories(repositories))
    //        │
    //        ▼
    // SearchRepositoryStore
    //        │
    //        ▼
    // repositoriesObservable 更新
    //        │
    //        ▼
    // RepositorySearchViewController の購読
    //        │
    //        ▼
    // tableView.reloadData()
    //        │
    //        ▼
    // numberOfRows が repositories.count になる
    // -------------------------------------------------------------
    //
    // つまりこのテストは
    // 「Store → View の反映」
    // が正しくつながっているかを確認している。
    func testReloadData() {

        // テスト対象の TableView。
        let tableView = dependency.viewController.tableView!

        // 初期状態では rows は 0 のはず。
        // これは検索結果がまだ空であることを示す。
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 0)

        // テスト用の Repository 群。
        let repositories: [GitHub.Repository] = [.mock(), .mock()]

        // Dispatcher に対して検索結果更新 Action を直接流す。
        //
        // ここでは ActionCreator や API を経由せず、
        // 「Store に repositories が入ったら View がどう反応するか」だけを見たいので
        // 直接 dispatch している。
        dependency.dispatcher.dispatch(.searchRepositories(repositories))

        // View への反映は Rx 経由・UI 更新を伴うため、
        // 少し遅れて反映される可能性を考慮して expectation で待つ。
        let expect = expectation(description: "waiting view reflection")

        // 少し遅らせて main queue 上で確認する。
        //
        // なぜ asyncAfter が必要か:
        // - Store の更新
        // - Observable の発火
        // - Binder による reloadData
        // - TableView の row 数反映
        //
        // までが完全に終わるのを待つためである。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {

            // rows 数が repositories.count と一致することを確認。
            XCTAssertEqual(tableView.numberOfRows(inSection: 0), repositories.count)
            expect.fulfill()
        }

        // UI 反映完了まで待機。
        wait(for: [expect], timeout: 1.1)
    }
}