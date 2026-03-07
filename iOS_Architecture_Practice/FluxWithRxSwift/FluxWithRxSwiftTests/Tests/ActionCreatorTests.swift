//
//  ActionCreatorTests.swift
//  FluxWithRxSwiftTests
//
//  このファイルは ActionCreator クラスのユニットテストを定義している。
//  ActionCreator は Flux アーキテクチャにおいて
//
//      「ユーザーイベント → Action 生成 → Dispatcher へ送信」
//
//  を担うコンポーネントである。
//
//  そのため、このテストでは主に次の点を検証する。
//
//  1. API 呼び出し後に正しい Action が dispatch されるか
//  2. clearRepositories が正しく dispatch されるか
//
//  テストは Flux アーキテクチャのイベントフローに沿って設計されている。
//
//  -------------------------------------------------------------
//                   Test Event
//                        │
//                        ▼
//                   ActionCreator
//                        │
//                        ▼
//                    Dispatcher
//                        │
//                        ▼
//                       Store
//  -------------------------------------------------------------
//
//  ActionCreatorTests は、このうち
//
//      ActionCreator → Dispatcher
//
//  の部分をテストしている。
//

import GitHub
import RxSwift
import XCTest
@testable import FluxWithRxSwift

// ActionCreator の振る舞いを検証する XCTestCase
final class ActionCreatorTests: XCTestCase {

    // MARK: - Dependency Container
    //
    // テスト用の依存関係をまとめた構造体。
    //
    // ActionCreator は通常、以下の依存を持つ。
    //
    //  - Dispatcher
    //  - GitHubApiSession
    //  - LocalCache
    //
    // テストでは実際の API を呼ばないようにするため
    // MockGitHubApiSession を使用する。
    //
    // -------------------------------------------------------------
    //                  Dependency
    //                       │
    //        ┌──────────────┼──────────────┐
    //        │                               │
    //        ▼                               ▼
    // MockGitHubApiSession              Dispatcher
    //        │                               │
    //        └──────────────┬──────────────┘
    //                       │
    //                       ▼
    //                  ActionCreator
    // -------------------------------------------------------------
    //
    private struct Dependency {

        /// GitHub API のモック実装
        /// ネットワーク通信を行わず、テストから結果を注入できる。
        let apiSession = MockGitHubApiSession()

        /// テスト対象の ActionCreator
        let actionCreator: ActionCreator

        /// Action を受け取る Dispatcher
        let dispatcher = Dispatcher()

        /// 依存関係を初期化する。
        ///
        /// ActionCreator には
        /// - dispatcher
        /// - apiSession
        /// - localCache
        ///
        /// を注入する。
        init() {
            self.actionCreator = ActionCreator(dispatcher: dispatcher,
                                               apiSession: apiSession,
                                               localCache: MockLocalCache())
        }
    }

    /// テストで利用する Dependency コンテナ
    private var dependency: Dependency!

    // MARK: - Setup

    /// 各テストの前に呼ばれる初期化処理。
    ///
    /// ここでは Dependency を再生成し、
    /// テスト間で状態が共有されないようにしている。
    override func setUp() {
        super.setUp()

        dependency = Dependency()
    }

    // MARK: - Test: searchRepositories

    /// searchRepositories のテスト。
    ///
    /// このテストでは以下のアルゴリズムを検証している。
    ///
    /// -------------------------------------------------------------
    ///              searchRepositories(query)
    ///                       │
    ///                       ▼
    ///                API 呼び出し
    ///                       │
    ///                       ▼
    ///              MockGitHubApiSession
    ///                       │
    ///                       ▼
    ///           setSearchRepositoriesResult()
    ///                       │
    ///                       ▼
    ///                ActionCreator
    ///                       │
    ///                       ▼
    ///                 Dispatcher.dispatch
    ///                       │
    ///                       ▼
    ///                .searchRepositories
    /// -------------------------------------------------------------
    ///
    /// テストでは
    ///
    /// 1. API 結果を Mock に注入
    /// 2. Dispatcher が受け取る Action を監視
    /// 3. dispatch された Action を検証
    ///
    /// という手順で検証する。
    func testSearchRepositories() {

        // モック Repository データ
        let repositories: [GitHub.Repository] = [.mock()]

        // モック Pagination データ
        let pagination = GitHub.Pagination.mock()

        // Dispatcher に流れる Action の回数をカウント
        var count: Int = 0

        // 非同期テスト用 expectation
        let expect = expectation(description: "waiting dispatcher.addRepositories")

        // Dispatcher に登録して Action を監視する。
        let disposable = dependency.dispatcher.register(callback: { action in

            // Action が dispatch されるたびにカウント
            count += 1

            // searchRepositories は 3 回目の dispatch で発生する
            guard count == 3 else {
                return
            }

            // Action が searchRepositories であることを確認
            guard case let .searchRepositories(_repositories) = action else {
                XCTFail("action must be .searchRepositories, but it is \(action)")
                return
            }

            // Repository 数が一致するか確認
            XCTAssertEqual(_repositories.count, repositories.count)

            // Repository が存在するか確認
            XCTAssertNotNil(_repositories.first)

            // Repository 名が一致するか確認
            XCTAssertEqual(_repositories.first?.fullName, repositories.first?.fullName)

            // expectation を満たす
            expect.fulfill()
        })

        // 検索 API 呼び出し
        dependency.actionCreator.searchRepositories(query: "repository-name")

        // Mock API に結果を注入
        dependency.apiSession.setSearchRepositoriesResult(repositories: repositories, pagination: pagination)

        // expectation が満たされるまで待機
        wait(for: [expect], timeout: 0.1)

        // Dispatcher 監視を解除
        disposable.dispose()
    }

    // MARK: - Test: clearRepositories

    /// clearRepositories のテスト。
    ///
    /// clearRepositories は
    ///
    /// -------------------------------------------------------------
    /// clearRepositories()
    ///        │
    ///        ▼
    /// Dispatcher.dispatch(.clearSearchRepositories)
    /// -------------------------------------------------------------
    ///
    /// という非常に単純なアルゴリズムを持つ。
    ///
    /// このテストでは
    ///
    /// ・ActionCreator.clearRepositories()
    /// ・Dispatcher に .clearSearchRepositories が流れる
    ///
    /// ことを確認している。
    func testClearUser() {

        // 非同期テスト用 expectation
        let expect = expectation(description: "waiting dispatcher.clearRepositories")

        // Dispatcher を監視
        let disposable = dependency.dispatcher.register(callback: { action in

            // Action が clearSearchRepositories であることを確認
            guard case .clearSearchRepositories = action else {
                XCTFail("action must be .clearSearchRepositories, but it is \(action)")
                return
            }

            // expectation を満たす
            expect.fulfill()
        })

        // clearRepositories 実行
        dependency.actionCreator.clearRepositories()

        // expectation が満たされるまで待機
        wait(for: [expect], timeout: 0.1)

        // Dispatcher 監視解除
        disposable.dispose()
    }
}