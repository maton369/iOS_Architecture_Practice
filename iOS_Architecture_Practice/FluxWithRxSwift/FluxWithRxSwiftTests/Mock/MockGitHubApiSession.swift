//
//  MockGitHubApiSession.swift
//  FluxWithRxSwiftTests
//
//
//  このファイルはテスト用の MockGitHubApiSession を実装している。
//  役割は「本物の GitHub API 通信の代わりに、テストから任意の値を流せるようにすること」である。
//
//  本番コードでは ActionCreator などが GitHubApiRequestable に依存しており、
//  実際の通信処理は GitHubApiSession のような具象実装が担当する。
//  しかしテストでは
//
//    ・ネットワークに依存したくない
//    ・検索APIがどんな引数で呼ばれたか確認したい
//    ・任意のタイミングで成功レスポンスを返したい
//
//  という要求があるため、このような Mock 実装を使う。
//
//  この Mock の重要なポイントは次の2つである。
//
//  1. searchRepositories(query:page:) が呼ばれたときの引数を Observable として外へ流す
//     → テスト側で「正しい query / page で呼ばれたか」を検証できる
//
//  2. テスト側から setSearchRepositoriesResult(...) を呼ぶと、
//     searchRepositories(...) が返した Observable に結果を流せる
//     → ActionCreator や Store の反応をテストできる
//
//  つまりこの Mock は
//
//    入力記録（spy 的役割）
//    +
//    テスト用レスポンス注入（stub 的役割）
//
//  の両方を持ったテストダブルになっている。
//

import GitHub
import RxCocoa
import RxSwift
@testable import FluxWithRxSwift

// MARK: - MockGitHubApiSession
//
// GitHubApiRequestable に準拠したテスト用モック。
// 本物の API 通信は行わず、Rx の Relay を使って
//
//   ・受け取った引数の観測
//   ・任意タイミングでの結果注入
//
// を可能にしている。
final class MockGitHubApiSession: GitHubApiRequestable {

    // MARK: - Public observable for test assertions

    /// searchRepositories(query:page:) が呼ばれたときの引数を外部から観測するための Observable。
    ///
    /// 型は (String, Int) で、
    /// - String: query
    /// - Int: page
    /// を表す。
    ///
    /// テスト側ではこれを subscribe して、
    ///
    ///   「ActionCreator が想定した query / page で API を呼んだか」
    ///
    /// を検証できる。
    ///
    /// たとえばテストでは次のような確認ができる。
    ///
    ///   - query が "swift" になっているか
    ///   - page が 1 になっているか
    let searchRepositoriesParams: Observable<(String, Int)>

    // MARK: - Internal relays

    /// searchRepositories(...) の呼び出しパラメータを内部的に流す Relay。
    ///
    /// PublishRelay を使っている理由:
    /// - 現在値を保持する必要はない
    /// - 「呼ばれた瞬間のイベント」を流したいだけ
    /// - error / completed を持たせたくない
    ///
    /// したがって、テスト時のイベント通知には PublishRelay がちょうどよい。
    private let _searchRepositoriesParams = PublishRelay<(String, Int)>()

    /// searchRepositories(...) が返す Observable の中身となる結果イベントを流す Relay。
    ///
    /// 型は
    ///
    ///   ([GitHub.Repository], GitHub.Pagination)
    ///
    /// であり、
    /// - 検索結果の Repository 配列
    /// - ページネーション情報
    ///
    /// をまとめて表している。
    ///
    /// テスト側が setSearchRepositoriesResult(...) を呼ぶと、
    /// この Relay にイベントが流れ、それを searchRepositories(...) の戻り値 Observable が受け取る。
    private let _searchRepositoriesResult = PublishRelay<([GitHub.Repository], GitHub.Pagination)>()

    // MARK: - Init

    /// 初期化時に、内部 Relay を外部公開用 Observable に変換している。
    ///
    /// ここで asObservable() している理由は、
    /// テストコード側から Relay の accept(...) を直接触らせず、
    /// 「購読だけ可能」にするためである。
    ///
    /// つまり、
    ///
    ///   書き込みは Mock 自身だけ
    ///   読み取りはテスト側も可能
    ///
    /// という責務分離になっている。
    init() {
        self.searchRepositoriesParams = _searchRepositoriesParams.asObservable()
    }

    // MARK: - GitHubApiRequestable

    /// Repository 検索 API のモック実装。
    ///
    /// アルゴリズム:
    ///
    /// 1. 受け取った query / page を _searchRepositoriesParams に流す
    ///    → テスト側が「どう呼ばれたか」を観測できる
    ///
    /// 2. _searchRepositoriesResult を Observable 化して返す
    ///    → テスト側が後から setSearchRepositoriesResult(...) を呼ぶと、その結果が流れる
    ///
    /// 本物の API 通信では
    ///
    ///   query / page
    ///      ↓
    ///   ネットワークリクエスト
    ///      ↓
    ///   レスポンス
    ///
    /// という流れになるが、この Mock では
    ///
    ///   query / page
    ///      ↓
    ///   呼び出し記録
    ///      ↓
    ///   テストから結果注入
    ///
    /// に置き換えている。
    func searchRepositories(query: String, page: Int) -> Observable<([Repository], Pagination)> {

        // (1) 呼び出しパラメータをイベントとして記録する。
        // これによりテスト側は
        // 「searchRepositories がどんな引数で呼ばれたか」
        // を subscribe で確認できる。
        _searchRepositoriesParams.accept((query, page))

        // (2) テスト側から注入される結果イベントの Observable を返す。
        //
        // 注意:
        // この Observable は PublishRelay ベースなので、
        // subscribe より前に accept されたイベントは受け取れない。
        // そのためテストでは通常、
        //
        //   1) 対象コードが searchRepositories(...) を呼ぶ
        //   2) その Observable に購読が貼られる
        //   3) その後 setSearchRepositoriesResult(...) を呼ぶ
        //
        // という順序で使う必要がある。
        return _searchRepositoriesResult.asObservable()
    }

    // MARK: - Test helper

    /// テスト側から検索結果を注入するための補助メソッド。
    ///
    /// アルゴリズム:
    ///
    /// 1. repositories と pagination をタプルにする
    /// 2. _searchRepositoriesResult に accept する
    /// 3. searchRepositories(...) が返した Observable を購読している側へ結果が流れる
    ///
    /// これにより、ActionCreator や ViewModel が
    ///
    ///   「API 成功時にどの Action を dispatch するか」
    ///   「Store をどう更新するか」
    ///
    /// をテストできる。
    ///
    /// つまりこのメソッドは
    ///
    ///   本物の API レスポンス到着
    ///
    /// をテスト側から擬似的に発生させるための装置である。
    func setSearchRepositoriesResult(repositories: [GitHub.Repository], pagination: GitHub.Pagination) {

        // 検索成功イベントを流す。
        // Relay を使っているため error / completed は流れず、
        // 必要なら複数回イベントを流すこともできる。
        _searchRepositoriesResult.accept((repositories, pagination))
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1. エラー系の注入手段を追加する
//    現状は成功結果しか流せない。
//    失敗ケースをテストしたいなら、PublishSubject を使うか、
//    Result<Event> を流す構造にして onError 相当を再現する方法がある。
//
// 2. 直近の呼び出し引数を保持する設計にする
//    Observable で観測する代わりに
//
//      var lastQuery: String?
//      var lastPage: Int?
//
//    のように保持して assert する方法もある。
//    ただし Rx ベースのテストではイベント観測の方が一貫しやすい。
//
// 3. 複数回呼び出し時の履歴保持
//    現状はイベントとして流すだけなので、履歴を明示的に残したい場合は
//    配列で保存する設計も考えられる。
//
// 4. PublishRelay のタイミング依存
//    PublishRelay は “購読開始後のイベントのみ” 流れる。
//    テストの順序を誤るとイベントを取り逃がすので注意が必要である。
//```