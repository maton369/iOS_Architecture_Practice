//
//  SearchRepositoryStoreTests.swift
//  FluxWithRxSwiftTests
//
//  このファイルは Flux アーキテクチャにおける Store の挙動をテストする。
//  対象となるのは SearchRepositoryStore であり、この Store は
//
//      ・検索された Repository 一覧
//      ・ページネーション情報
//      ・検索状態
//
//  などを保持する「アプリ状態の一部」を管理する役割を持つ。
//
//  Flux アーキテクチャでは、Store は次のようなイベントフローで更新される。
//
// -------------------------------------------------------------
//                 User Event
//                      │
//                      ▼
//                ActionCreator
//                      │
//                      ▼
//                  Dispatcher
//                      │
//                      ▼
//                    Store
//                      │
//                      ▼
//                     View
// -------------------------------------------------------------
//
//  このテストでは
//
//      Dispatcher → Store
//
//  の部分のアルゴリズムが正しく動作するかを確認している。
//
//  つまり
//
//      「Action が dispatch されたとき Store の状態が正しく更新されるか」
//
//  を検証するユニットテストである.
//

import GitHub
import RxCocoa
import RxSwift
import XCTest
@testable import FluxWithRxSwift

// SearchRepositoryStore の振る舞いをテストする XCTestCase
final class SearchRepositoryStoreTests: XCTestCase {

    // MARK: - Dependency Container
    //
    // テスト用の依存関係をまとめた構造体。
    //
    // Store は通常 Dispatcher に登録され、
    // dispatch された Action を受け取って状態を更新する。
    //
    // そのためテストでは次の構造を作る。
    //
    // -------------------------------------------------------------
    //                    Dependency
    //                        │
    //        ┌───────────────┼───────────────┐
    //        │                               │
    //        ▼                               ▼
    //     Dispatcher                  SearchRepositoryStore
    //        │                               │
    //        └───────────────dispatch────────┘
    // -------------------------------------------------------------
    //
    // Dispatcher に Action を送ることで、
    // Store の状態変化を再現できる。
    //
    private struct Dependency {

        /// テスト対象の Store
        let store: SearchRepositoryStore

        /// Action を送信する Dispatcher
        let dispatcher = Dispatcher()

        /// Store は Dispatcher に登録して初期化される
        init() {
            self.store = SearchRepositoryStore(dispatcher: dispatcher)
        }
    }

    /// テスト用 Dependency
    private var dependency: Dependency!

    // MARK: - Setup

    /// 各テストの前に呼ばれる初期化処理。
    ///
    /// 新しい Dependency を作成し、
    /// Store の状態を初期化する。
    override func setUp() {
        super.setUp()

        dependency = Dependency()
    }

    // MARK: - Test: Add Repositories

    /// Repository 追加のテスト。
    ///
    /// このテストでは
    ///
    ///     Action.searchRepositories
    ///
    /// が dispatch されたとき、
    ///
    ///     Store.repositories
    ///
    /// が正しく更新されるかを確認する。
    ///
    /// アルゴリズムは次の通り。
    ///
    /// -------------------------------------------------------------
    /// dispatch(.searchRepositories)
    ///          │
    ///          ▼
    ///      Dispatcher
    ///          │
    ///          ▼
    ///  SearchRepositoryStore
    ///          │
    ///          ▼
    /// repositories.accept(newRepositories)
    ///          │
    ///          ▼
    /// repositoriesObservable
    ///          │
    ///          ▼
    ///       Test Assertion
    /// -------------------------------------------------------------
    ///
    /// このテストでは
    ///
    /// ・Observable を購読
    /// ・Action dispatch
    /// ・Store 更新を検証
    ///
    /// という流れで検証している。
    func testAddRepositories() {

        // 初期状態では repositories は空である
        XCTAssertTrue(dependency.store.repositories.isEmpty)

        // モック Repository データ
        let repositories: [GitHub.Repository] = [.mock(), .mock()]

        // 非同期イベント待機用 expectation
        let expect = expectation(description: "waiting store changes")

        // repositoriesObservable を購読する。
        //
        // skip(1) を使う理由：
        // BehaviorRelay は subscribe 時に現在値を emit するため
        // 初期値イベントを無視する必要がある。
        let disposable = dependency.store.repositoriesObservable
            .skip(1)
            .subscribe(onNext: { _repositories in

                // Repository 数が一致するか確認
                XCTAssertEqual(_repositories.count, repositories.count)

                // Repository が存在するか確認
                XCTAssertNotNil(_repositories.first)

                // Repository 名が一致するか確認
                XCTAssertEqual(_repositories.first?.fullName,
                               repositories.first?.fullName)

                // expectation を満たす
                expect.fulfill()
            })

        // Dispatcher に Action を送信
        dependency.dispatcher.dispatch(.searchRepositories(repositories))

        // 非同期イベントを待機
        wait(for: [expect], timeout: 0.1)

        // 購読解除
        disposable.dispose()

        // Store の状態が更新されたことを確認
        XCTAssertEqual(dependency.store.repositories.count, repositories.count)
    }

    // MARK: - Test: Clear Repositories

    /// Repository クリアのテスト。
    ///
    /// clearSearchRepositories が dispatch されたとき、
    ///
    ///     repositories が空になる
    ///
    /// ことを確認する。
    ///
    /// アルゴリズムは次の通り。
    ///
    /// -------------------------------------------------------------
    /// dispatch(.clearSearchRepositories)
    ///          │
    ///          ▼
    ///      Dispatcher
    ///          │
    ///          ▼
    ///  SearchRepositoryStore
    ///          │
    ///          ▼
    /// repositories.accept([])
    ///          │
    ///          ▼
    /// repositoriesObservable
    ///          │
    ///          ▼
    ///       Test Assertion
    /// -------------------------------------------------------------
    ///
    /// まず Repository を追加し、
    /// その後 clearSearchRepositories を dispatch して
    /// Store が空になることを確認する。
    func testClearRepositories() {

        // モック Repository
        let repositories: [GitHub.Repository] = [.mock(), .mock()]

        // まず Repository を追加
        dependency.dispatcher.dispatch(.searchRepositories(repositories))

        // Store に Repository が存在することを確認
        XCTAssertFalse(dependency.store.repositories.isEmpty)

        // 非同期イベント待機用 expectation
        let expect = expectation(description: "waiting store changes")

        // Observable を購読
        let disposable = dependency.store.repositoriesObservable
            .skip(1)
            .subscribe(onNext: { repositories in

                // repositories が空になることを確認
                XCTAssertTrue(repositories.isEmpty)

                expect.fulfill()
            })

        // Repository をクリア
        dependency.dispatcher.dispatch(.clearSearchRepositories)

        // Store 更新を待機
        wait(for: [expect], timeout: 0.1)

        // 購読解除
        disposable.dispose()

        // 最終状態を確認
        XCTAssertTrue(dependency.store.repositories.isEmpty)
    }
}