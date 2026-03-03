//
//  ReposLikesUseCase.swift
//  CleanGitHub
//
//  Created by 加藤寛人 on 2018/09/19.
//  Copyright © 2018年 Peaks. All rights reserved.
//
//  このファイルは Clean Architecture における Use Case（ユースケース）を実装している。
//  Use Case は「アプリケーション固有の業務ルール（Application Business Rules）」を担い、
//
//  - Entity（ドメインモデル）を組み合わせて
//  - 外部（API/DB/キャッシュ等）に依存せずに
//  - ある“目的の処理”を達成するための手順（アルゴリズム）を定義する
//
//  という役割を持つ。
//
//  Clean Architecture の円でいうと、Use Case は “内側” にあり、
//  外側（Interface Adapters / Frameworks & Drivers）に対しては
//  - Protocol（境界インターフェース）
//  - Output（結果通知）
//  を通してのみやり取りする。
//
//  本ファイルが提供するユースケースは大きく3つ。
//  1) キーワード検索して Repo を取得し、Like 状態と合成した一覧を返す
//  2) Like 済み Repo 一覧（お気に入り一覧）を構築して返す
//  3) Like 状態を保存し、検索結果一覧・お気に入り一覧の両方を整合的に更新する
//
//  これらは UI が欲しい “表示用の材料” を Use Case が作る、典型的な Clean Architecture の形である。
//  UI は “どう取得するか” ではなく “Use Case の出力を描画する” だけに寄せられる。
//

import Foundation

// MARK: - Use Case公開インターフェース（Input Port）
//
// ReposLikesUseCaseProtocol は、Use Case が外側（Interface Adapters）へ公開する入口である。
// Clean Architecture の用語だと Input Port に相当する。
// Presenter / ViewModel / Controller などは、この Protocol を通して Use Case を呼び出す。
//
// 重要ポイント:
// - 外側は具象クラス（ReposLikesUseCase）に依存しない（protocol に依存）
// - Use Case は外側のフレームワーク（UIKitなど）を知らない
protocol ReposLikesUseCaseProtocol: AnyObject {

    /// キーワードを使ったサーチを開始する。
    /// 検索結果RepoとLike状態を合成した RepoStatus の配列を output に通知する。
    func startFetch(using keywords: [String])

    /// お気に入り済みリポジトリ一覧の取得を開始する。
    /// Like一覧（ID->Bool）と Repo情報を突き合わせ、liked の RepoStatus だけを output に通知する。
    func collectLikedRepos()

    /// お気に入りの追加・削除を行う。
    /// 永続化（likesGateway.save）を行い、成功したら内部の statusList/likesList を更新して output に通知する。
    func set(liked: Bool, for repo: GitHubRepo.ID)

    // 外側（Presenter/ViewModel等）が “後から注入” する依存（DI）。
    // Clean Architecture 的には initializer injection が理想だが、教材として property injection にしている可能性が高い。

    /// Use Case の結果を外側へ通知する Output Port。
    var output: ReposLikesUseCaseOutput! { get set }

    /// Repo取得のためのゲートウェイ（Repository/データ取得境界）。
    var reposGateway: ReposGatewayProtocol! { get set }

    /// Like状態取得・保存のためのゲートウェイ。
    var likesGateway: LikesGatewayProtocol! { get set }
}

// MARK: - Use Case Output（Output Port）
//
// Use Case は “結果” を return で返さず、Output を通して通知する設計。
// これは非同期処理（ネットワーク/DB）を内包しやすく、UI側の更新にも相性が良い。
// Clean Architecture 用語では Output Port。
protocol ReposLikesUseCaseOutput {

    /// 検索結果（Repo + Like状態）が更新されたときに呼ばれる。
    /// UI はここで受け取った配列を描画する（テーブル更新など）。
    func useCaseDidUpdateStatuses(_ repoStatuses: [GitHubRepoStatus])

    /// お気に入り一覧（liked のみ）が更新されたときに呼ばれる。
    func useCaseDidUpdateLikesList(_ likesList: [GitHubRepoStatus])

    /// Use Case 関連の処理でエラーが発生したときに呼ばれる。
    /// UI はアラートやエラー表示を行う。
    func useCaseDidReceiveError(_ error: Error)
}

// MARK: - Gateways（外部データ取得の境界）
//
// Gateway は Use Case から見た “外部への窓口”。
// 具体実装は外側に置かれ、Use Case は Protocol にのみ依存する。
// これにより、ネットワーク/DB/キャッシュ差し替えやテストが容易になる。

protocol ReposGatewayProtocol {

    /// キーワード検索で Repo を取得する。
    /// 取得元（GitHub API, キャッシュ等）は Use Case からは見えない。
    func fetch(using keywords: [String],
               completion: @escaping (Result<[GitHubRepo]>) -> Void)

    /// ID指定で Repo を取得する。
    /// お気に入り一覧の “ID一覧 -> Repo詳細取得” などで使われる。
    func fetch(using ids: [GitHubRepo.ID],
               completion: @escaping (Result<[GitHubRepo]>) -> Void)
}

protocol LikesGatewayProtocol {

    /// 指定ID群の Like 状態（ID -> Bool）を取得する。
    /// “Repo一覧に対して Like 状態を付与する” ユースケースで使われる。
    func fetch(ids: [GitHubRepo.ID],
               completion: @escaping (Result<[GitHubRepo.ID: Bool]>) -> Void)

    /// 指定IDの Like 状態を保存する（永続化）。
    /// 成功時は保存された状態（Bool）を返す想定。
    func save(liked: Bool,
              for id: GitHubRepo.ID,
              completion: @escaping (Result<Bool>) -> Void)

    /// すべての Like 状態一覧（ID -> Bool）を取得する。
    /// “お気に入り一覧” 構築のために使われる。
    func allLikes(completion: @escaping (Result<[GitHubRepo.ID: Bool]>) -> Void)
}

// MARK: - Use Case Implementation
//
// ReposLikesUseCase は “手順（アルゴリズム）” を実装する本体。
// 依存はすべて Protocol 経由で注入されるため、外部環境から独立している。
final class ReposLikesUseCase: ReposLikesUseCaseProtocol {

    // MARK: Dependencies (injected)

    /// Output Port（結果通知先）。
    var output: ReposLikesUseCaseOutput!

    /// Repo 取得ゲートウェイ。
    var reposGateway: ReposGatewayProtocol!

    /// Like 取得・保存ゲートウェイ。
    var likesGateway: LikesGatewayProtocol!

    // MARK: Internal State (Use Case内で保持する整合性)
    //
    // Use Case が内部に “表示用の状態” を保持しているのが特徴。
    // - statusList: 検索結果一覧（Repo + Like状態）
    // - likesList : お気に入り一覧（likedのみ）
    //
    // set(liked:for:) 時に両方を更新し、UIを整合的に更新できるようにしている。
    private var statusList = GitHubRepoStatusList(repos: [], likes: [:])
    private var likesList = GitHubRepoStatusList(repos: [], likes: [:])

    // MARK: - Use Case 1: Search + Like合成
    //
    // キーワードで Repo を検索し、取得できた Repo 群に対して Like 状態を取得して合成し、
    // RepoStatus の配列として output に通知する。
    //
    // アルゴリズム（段階的）:
    //
    //   (1) reposGateway.fetch(keywords) で Repo一覧を取得
    //   (2) Repo一覧から id 配列を作る
    //   (3) likesGateway.fetch(ids) で Like状態辞書を取得
    //   (4) Repo + Like を合成して GitHubRepoStatusList を作る
    //   (5) 内部の statusList を更新し、output に statuses を通知する
    //
    // なぜ2段階か:
    // - Repo情報とLike情報はデータソースが異なる（API vs ローカル等）
    // - Use Case が両者を統合することで、UIは “合成済みの結果” だけ扱えば良い
    func startFetch(using keywords: [String]) {

        // (1) Repo検索（外部境界：ReposGateway）
        reposGateway.fetch(using: keywords) { [weak self] reposResult in
            guard let self = self else { return }

            switch reposResult {

            case .failure(let e):
                // Repo取得失敗を Use Case エラーとして外へ通知する。
                // FetchingError はこのファイル外で定義されている想定（ドメイン/アプリ層エラー）。
                self.output
                    .useCaseDidReceiveError(FetchingError.failedToFetchRepos(e))

            case .success(let repos):
                // (2) Repo一覧からID配列を抽出
                let ids = repos.map { $0.id }

                // (3) Like状態を取得（外部境界：LikesGateway）
                self.likesGateway
                    .fetch(ids: ids) { [weak self] likesResult in
                        guard let self = self else { return }

                        switch likesResult {

                        case .failure(let e):
                            // Like取得失敗を通知
                            self.output
                                .useCaseDidReceiveError(
                                    FetchingError.failedToFetchLikes(e))

                        case .success(let likes):
                            // (4) Repo + Like を合成し、コレクションルール込みで保持する
                            let statusList = GitHubRepoStatusList(
                                repos: repos, likes: likes
                            )

                            // (5) 結果を保持（次の like 更新で整合性更新するため）
                            self.statusList = statusList

                            // UIへ通知（合成済み statuses）
                            self.output.useCaseDidUpdateStatuses(statusList.statuses)
                        }
                }
            }
        }
    }

    // MARK: - Use Case 2: Liked Repos collection
    //
    // お気に入り一覧を構築する。
    // Like一覧は “ID->Bool” であり、Repoの詳細は別経路で取得する必要があるため、
    // まず likes を取り、次に ids で repos を取る2段階になる。
    //
    // アルゴリズム:
    //   (1) likesGateway.allLikes で全 like 状態を取得
    //   (2) liked のID群（＝辞書の keys）を取り出す
    //   (3) reposGateway.fetch(ids) でRepo詳細を取得
    //   (4) Repo + allLikes を合成し、trimmed=true で liked のみの List を作る
    //   (5) 内部の likesList を更新し、output に通知する
    func collectLikedRepos() {

        // (1) 全 like 状態を取得
        likesGateway.allLikes { [weak self] result in
            guard let self = self else { return }

            switch result {

            case .failure(let e):
                self.output
                    .useCaseDidReceiveError(
                        FetchingError.failedToFetchLikes(e))

            case .success(let allLikes):

                // (2) Like辞書の keys を Repo ID 群として取り出す
                // ここでは “like辞書に存在するID = 取得対象” という前提。
                // allLikes の中身が false を含む場合は、keys をそのまま使うと “未likedも含む” になるので仕様確認が重要。
                // （一般には likes は liked のみ保存する設計が多い）
                let ids = Array(allLikes.keys)

                // (3) ID指定で Repo 詳細を取得
                self.reposGateway.fetch(using: ids) { [weak self] reposResult in
                    guard let self = self else { return }

                    switch reposResult {

                    case .failure(let e):
                        // ここはエラー種別が failedToFetchLikes になっているが、
                        // 意味としては “Repo取得失敗” なので failedToFetchRepos の方が自然かもしれない（要見直し）。
                        self.output
                            .useCaseDidReceiveError(
                                FetchingError.failedToFetchLikes(e))

                    case .success(let repos):
                        // (4) Repo + allLikes を合成して liked のみへトリム
                        let likesList = GitHubRepoStatusList(
                            repos: repos,
                            likes: allLikes,
                            trimmed: true
                        )

                        // (5) 結果を保持し、UIへ通知
                        self.likesList = likesList
                        self.output.useCaseDidUpdateLikesList(likesList.statuses)
                    }
                }
            }
        }
    }

    // MARK: - Use Case 3: Like toggle (save + consistent update)
    //
    // Likeの追加/削除を永続化し、その結果を “検索結果一覧” と “お気に入り一覧” の両方へ反映する。
    //
    // アルゴリズム:
    //   (1) likesGateway.save(liked, id) で永続化
    //   (2) 成功したら isLiked（保存結果）を取得
    //   (3) statusList と likesList の双方を id 指定で更新する
    //   (4) 更新後の両一覧を output へ通知する
    //
    // このユースケースの重要性:
    // - 画面が複数（検索画面とお気に入り画面）あっても状態を矛盾なく更新できる
    // - “保存成功” を起点に state を更新するので、UIが先走って不整合になりにくい
    func set(liked: Bool, for id: GitHubRepo.ID) {

        // (1) Like状態を保存（外部境界）
        likesGateway.save(liked: liked, for: id)
        { [weak self] likesResult in
            guard let self = self else { return }

            switch likesResult {

            case .failure:
                // 保存失敗 → UIへエラー通知
                self.output
                    .useCaseDidReceiveError(SavingError.failedToSaveLike)

            case .success(let isLiked):
                do {
                    // (3) 内部保持の2つのリストを更新
                    // statusList: 検索結果（表示中のRepo群）
                    // likesList : お気に入り一覧（likedのみ or その時点の保持一覧）
                    //
                    // どちらにも対象IDが存在しない場合は notFoundRepo が投げられる可能性がある。
                    try self.statusList.set(isLiked: isLiked, for: id)
                    try self.likesList.set(isLiked: isLiked, for: id)

                    // (4) 両方の最新状態を通知
                    self.output
                        .useCaseDidUpdateStatuses(self.statusList.statuses)
                    self.output
                        .useCaseDidUpdateLikesList(self.likesList.statuses)

                } catch {
                    // 更新失敗（対象が存在しない等）を保存失敗として扱っている。
                    // 実務では “notFound” と “save失敗” を分けるとデバッグしやすい。
                    self.output
                        .useCaseDidReceiveError(SavingError.failedToSaveLike)
                }
            }
        }
    }
}

//
// MARK: - Use Case観点での改善メモ（読み手の理解を深めるため）
//
// 1) スレッド境界（UI更新）
//    completion がバックグラウンドで返る場合、output を main thread で呼ぶ保証が必要。
//    Use Case が main dispatch するか、Presenter が受けて main に戻すか、設計を固定すると安全。
//
// 2) collectLikedRepos の ids 抽出
//    allLikes が [ID: Bool] で false を含むなら、keys をそのまま使うと “未likedも取得対象” になる。
//    仕様として likes は liked のみ保存する、または filter { $0.value } で true のみ抽出するのが明確。
//
// 3) エラー種別の整合性
//    collectLikedRepos 内の reposGateway.fetch(ids) failure が failedToFetchLikes になっているのは違和感がある。
//    failedToFetchRepos に寄せると原因追跡がしやすい。
//
// 4) statusList / likesList の更新戦略
//    likesList は trimmed=true で liked のみを保持しているため、unlike した瞬間に “対象がList内に存在しない” ケースがあり得る。
//    その場合は set が throw して catch に入り、SavingError 扱いになる可能性がある。
//    - likesList は “likedのみ表示” なので、unlike 時は remove する挙動が自然
//    - あるいは likesList の更新を try せず、存在しないなら無視する戦略にする
//    など、ユースケース上の意図を明文化すると堅牢になる。
//```