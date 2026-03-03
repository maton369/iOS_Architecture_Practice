//
//  ActionCreator.swift
//  FluxExample
//
//
//  このファイルは Flux アーキテクチャにおける ActionCreator を実装している。
//  ActionCreator は「ユーザ操作や外部イベント」を起点にして、
//  - 必要なら副作用（API通信、ローカルキャッシュ読み書き）を実行し
//  - その結果を Action として Dispatcher に流す（dispatch）
//  という役割を持つ。
//
//  Flux の登場人物をざっくり対応付けると以下の通り。
//  - ActionCreator: “何が起きたか” を Action にして dispatch する（副作用もここに置かれやすい）
//  - Dispatcher   : Action を配信するハブ（イベントバス）
//  - Store        : Action を受けて状態(State)を更新し、Viewに通知する
//  - View         : Store の状態を描画し、ユーザ操作を ActionCreator に伝える
//
//  本ファイルのアルゴリズムの本質は、Flux の単方向データフローを守ること。
//    View -> ActionCreator -> Dispatcher -> Store -> View
//
//  特に searchRepositories(query:page:) は、
//  (1) “検索開始” を Action で通知
//  (2) “ローディング開始” を Action で通知
//  (3) API を叩く（副作用）
//  (4) 成功/失敗に応じて Action を dispatch
//  (5) “ローディング終了” を Action で通知
//  という、非同期処理の典型的な Flux パターンを実装している。
//

import GitHub

// MARK: - ActionCreator
//
// final: 継承で dispatch の規約が崩れると Flux のフローが壊れやすいので固定する意図。
// ActionCreator は “状態を持たない” のが基本で、状態は Store が持つ。
// ただし、外部永続化（LocalCache）を扱う場合はここで読み書きし、Store に反映させる設計を取ることが多い。
final class ActionCreator {

    // MARK: Dependencies

    /// Action を流すための Dispatcher。
    /// .shared をデフォルトにすることで、アプリ内の一貫したフローを作る。
    /// テストでは差し替え可能。
    private let dispatcher: Dispatcher

    /// GitHub API へのアクセス抽象。
    /// GitHubApiRequestable に依存することで、実装（本番/モック）を差し替え可能にする。
    private let apiSession: GitHubApiRequestable

    /// ローカルキャッシュ抽象（お気に入りなどの永続化）。
    /// LocalCacheable に依存することで、UserDefaults/DB/インメモリなどの差し替えができる。
    private let localCache: LocalCacheable

    // MARK: Init (DI)

    /// 依存注入（DI）。
    ///
    /// - dispatcher: Action 配信ハブ
    /// - apiSession: 外部APIアクセス（副作用）
    /// - localCache: 永続化（副作用）
    ///
    /// Flux では副作用を ActionCreator に寄せる設計が多いが、
    /// 大規模になると Middleware / Effect 層に分離する流派もある。
    init(dispatcher: Dispatcher = .shared,
         apiSession: GitHubApiRequestable = GitHubApiSession.shared,
         localCache: LocalCacheable = LocalCache.shared) {
        self.dispatcher = dispatcher
        self.apiSession = apiSession
        self.localCache = localCache
    }
}

// MARK: - Search Actions
//
// 検索に関する “入力（ユーザ操作）” と “副作用（API通信）” を Action に変換して dispatch する。
extension ActionCreator {

    /// リポジトリ検索を実行する。
    ///
    /// Flux 的アルゴリズム（重要）:
    /// 1) 検索クエリを Store に伝える（検索欄の状態をStateに残すため）
    /// 2) ローディング開始を伝える（isRepositoriesFetching=true）
    /// 3) API通信を開始する（副作用）
    /// 4) 成功: 検索結果とページ情報を Action として dispatch
    ///    失敗: エラーを Action として dispatch
    /// 5) どちらの場合も最後にローディング終了を伝える（isRepositoriesFetching=false）
    ///
    /// ポイント:
    /// - “状態更新” は Store がやる。ActionCreator は Action を流すだけ。
    /// - UI は Store の state を見てローディング表示/結果表示を切り替える。
    /// - この関数は「検索ユースケースの副作用＋Action発火の順序」を規定している。
    func searchRepositories(query: String, page: Int = 1) {

        // (1) 検索クエリの更新を Action として dispatch
        // これにより Store は state.searchQuery を更新し、UI は現在のクエリを状態として参照できる。
        dispatcher.dispatch(.searchQuery(query))

        // (2) ローディング開始を通知
        // UI は state.isRepositoriesFetching を見て spinner を出す等ができる。
        dispatcher.dispatch(.isRepositoriesFetching(true))

        // (3) API通信（副作用）
        // completion の capture に [dispatcher] を使っているのは、
        // self を強参照しない（循環参照リスクを下げる）ための工夫。
        // ただし apiSession / localCache などが必要なら self を参照する必要が出るため設計方針が重要。
        apiSession.searchRepositories(query: query, page: page) { [dispatcher] result in

            // (4) 結果に応じて Action を dispatch
            switch result {

            case let .success((repositories, pagination)):
                // 成功時:
                // - 検索結果リストを Store に渡す
                dispatcher.dispatch(.searchRepositories(repositories))

                // - ページング情報を Store に渡す（次ページ取得UIなどに利用）
                dispatcher.dispatch(.searchPagination(pagination))

            case let .failure(error):
                // 失敗時:
                // - エラー状態を Store に渡す（アラート表示やエラー画面に利用）
                dispatcher.dispatch(.error(error))
            }

            // (5) 最後にローディング終了（成功/失敗どちらでも必ず実行）
            // ここがあることで、UI の loading 表示が必ず止まる。
            dispatcher.dispatch(.isRepositoriesFetching(false))
        }
    }

    /// 検索フィールドの編集中フラグを更新する。
    ///
    /// これは “UI状態” だが、Flux では UI状態も Store に集約する流派がある。
    /// 例: 編集中は候補リストを出す、検索ボタンを活性化する等。
    func setIsSearchFieldEditing(_ isEditing: Bool) {
        dispatcher.dispatch(.isSearchFieldEditing(isEditing))
    }

    /// 検索結果をクリアする。
    ///
    /// 例: クエリを消した、別タブへ移動した、などのタイミングで呼ばれる。
    /// Store はこの Action を受けて repositories を空にする。
    func clearRepositories() {
        dispatcher.dispatch(.clearSearchRepositories)
    }
}

// MARK: - Favorite Actions
//
// お気に入り操作は “永続化（LocalCache）” という副作用を伴う。
// ActionCreator が localCache を更新し、その結果の配列を Store に反映する Action を dispatch する。
extension ActionCreator {

    /// お気に入りに追加する。
    ///
    /// アルゴリズム:
    /// 1) localCache から現在のお気に入り配列を取得
    /// 2) repository を追加した新配列を作る
    /// 3) localCache に保存（副作用）
    /// 4) Store に新配列を Action として dispatch（状態の正）
    ///
    /// 注意:
    /// - 重複追加の防止（同じidが既に入っている場合）を入れるかは仕様次第
    /// - スレッド安全性（複数スレッドからの更新）を考えるなら localCache 実装側の責務も重要
    func addFavoriteRepository(_ repository: GitHub.Repository) {
        let repositories = localCache[.favorites] + [repository]
        localCache[.favorites] = repositories
        dispatcher.dispatch(.setFavoriteRepositories(repositories))
    }

    /// お気に入りから削除する。
    ///
    /// アルゴリズム:
    /// 1) localCache から現在のお気に入り配列を取得
    /// 2) repository.id が一致しないものだけ残す（filter）
    /// 3) localCache に保存（副作用）
    /// 4) Store に新配列を dispatch
    ///
    /// id ベースで削除しているため、参照同一性ではなく “同じリポジトリ” を安定して削除できる。
    func removeFavoriteRepository(_ repository: GitHub.Repository) {
        let repositories = localCache[.favorites].filter { $0.id != repository.id }
        localCache[.favorites] = repositories
        dispatcher.dispatch(.setFavoriteRepositories(repositories))
    }

    /// お気に入り一覧を読み込み、Store に反映する。
    ///
    /// アルゴリズム:
    /// 1) localCache から favorites を取得
    /// 2) Store に dispatch
    ///
    /// 画面表示時（初回ロード）や、アプリ起動時の復元などで使う。
    func loadFavoriteRepositories() {
        dispatcher.dispatch(.setFavoriteRepositories(localCache[.favorites]))
    }
}

// MARK: - Others
//
// 画面上の選択状態など、検索/お気に入り以外の小さな状態更新を Action として流す。
extension ActionCreator {

    /// 選択中のリポジトリを更新する。
    ///
    /// アルゴリズム:
    /// - 選択された repository（または nil）を Store に伝える
    /// - Store が state.selectedRepository を更新し、View が詳細表示などを切り替える
    ///
    /// nil を許容しているのは「選択解除」「初期状態」を表すため。
    func setSelectedRepository(_ repository: GitHub.Repository?) {
        dispatcher.dispatch(.selectedRepository(repository))
    }
}