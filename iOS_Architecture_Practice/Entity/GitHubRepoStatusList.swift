//
//  GitHubRepoStatusList.swift
//  CleanGitHub
//
//
//  このファイルは Clean Architecture（クリーンアーキテクチャ）における Entity / Value Object 的な構造を扱う。
//  具体的には、GitHubRepo（Repository のEntity）に対して
//  「ユーザの like 状態（isLiked）」という “ドメイン上の状態” を合成し、
//  それらを一貫したルールで管理するためのコレクション（List）を提供している。
//
//  ここでの重要ポイントは次の2つ。
//
//  1) GitHubRepoStatus は “Repo + Like状態” を表す複合ドメインモデル
//     - Repo は外部から取得した情報（API）
//     - Like はユーザがアプリ内で持つ状態（ローカル保存など）
//     これらを UI 層ではなくドメイン層で合成することで、ユースケースが簡潔になる。
//
//  2) GitHubRepoStatusList は “コレクションに対するドメインルール” を閉じ込めた型
//     - Repo は id で同一性を持つ
//     - 同じ repo が複数回入らないようにユニーク化する
//     - append 時は「新しい情報で上書き」する（古いものを消す）
//     - trimmed=true の場合は liked のものだけに絞る
//     - like 更新は id 指定で行い、存在しない場合はドメインエラーを返す
//
//  Clean Architecture 的には、こうした “集合操作のルール” を UseCase や UI に散らすのではなく、
//  Entity / Domain Model 側に寄せると変更に強くなる。
//

import Foundation

// MARK: - GitHubRepoStatus
//
// GitHubRepo（Entity）と、そのRepoに対するユーザ状態（isLiked）を合成したドメインモデル。
// 「Repoそれ自体」と「ユーザがどう扱っているか」は別物だが、ユースケースでは一緒に扱うことが多い。
// そこでこの型が橋渡しをする。
//
// Equatable を repo 同一性（id）で定義しているため、
// - isLiked が違っても「同じRepo」とみなして同一性を判断できる。
// つまりこの型の “Identity” は repo.id に依存している。
struct GitHubRepoStatus: Equatable {

    /// 対象のリポジトリ（Entity）。
    /// Repo 自体の同一性は repo.id が担う。
    let repo: GitHubRepo

    /// ユーザがこのRepoを like（お気に入り）しているかどうか。
    /// ドメイン上は “ユーザの選好状態” として扱える。
    let isLiked: Bool

    // MARK: Equatable (同一性に基づく等価性)
    //
    // 「同じRepoかどうか」を repo.id で判定する。
    // isLiked は “属性（状態）” であり、同一性には含めないという設計。
    //
    // 例:
    // - (repo: A, isLiked: true)
    // - (repo: A, isLiked: false)
    // は “同じRepo” なので等価とみなす。
    //
    // これにより、コレクションの unique 化で「Repo重複」を自然に排除できる。
    static func == (lhs: GitHubRepoStatus, rhs: GitHubRepoStatus) -> Bool {
        return lhs.repo == rhs.repo
    }
}

// MARK: - Array<GitHubRepoStatus> convenience initializer
//
// repos（外部取得）と likes（ローカル状態）を合成して GitHubRepoStatus 配列を生成する。
// ここを extension にしておくことで、List 側の初期化ロジックが読みやすくなる。
extension Array where Element == GitHubRepoStatus {

    /// repos と likes から status 配列を作る。
    ///
    /// - repos: GitHub から取得した Repo 一覧
    /// - likes: repo.id をキーにした like 状態辞書
    ///
    /// アルゴリズム:
    /// 1) repos を順に走査して status を生成する
    /// 2) likes[repo.id] が存在すればその値を使い、なければ false（未liked）にする
    ///
    /// ここで “likes に存在しない = false” と決め打っているのはドメインルールであり、
    /// UseCase や UI に散らすより Domain 側に集約した方が保守性が高い。
    init(repos: [GitHubRepo], likes: [GitHubRepo.ID: Bool]) {
        self = repos.map { repo in
            GitHubRepoStatus(
                repo: repo,
                isLiked: likes[repo.id] ?? false
            )
        }
    }
}

// MARK: - GitHubRepoStatusList
//
// GitHubRepoStatus の集合を “ドメインルール付き” で管理するコレクション型。
// Array を直接扱うのではなく、この型に閉じ込めることで、
// - 重複排除
// - 追加のマージ戦略
// - like 更新の失敗（notFound）
// - trim（likedのみ）
// などのルールを一箇所に固定できる。
struct GitHubRepoStatusList {

    // MARK: - Domain Error
    //
    // List に対する操作が成立しない場合のドメインエラー。
    // ここでは “指定idのrepoが存在しない” を表現している。
    enum Error: Swift.Error {
        case notFoundRepo(ofID: GitHubRepo.ID)
    }

    // MARK: - Stored statuses
    //
    // 外部からは読み取りのみ許可し、更新は List のメソッド経由にすることで
    // ドメインルール（重複排除など）が破られにくくなる。
    private(set) var statuses: [GitHubRepoStatus]

    // MARK: - Init
    //
    // repos と likes から status を生成し、ユニーク化した上で、必要なら liked のみへトリムする。
    //
    // trimmed の意味:
    // - false: 全 repos を保持する（liked/未liked混在）
    // - true : liked のものだけを保持する（お気に入り一覧用など）
    init(repos: [GitHubRepo], likes: [GitHubRepo.ID: Bool], trimmed: Bool = false) {

        // (1) repos + likes を合成して status 配列を作る
        statuses = Array(repos: repos, likes: likes)

            // (2) Repo の重複を排除する
            //
            // unique(resolve:) は、おそらく同一要素が複数ある場合の解決戦略を指定できる拡張メソッド。
            // resolve: { old, new in ... } の形で “どちらを残すか” を決める。
            //
            // ここでは .ignoreNewOne を選んでいるため、
            // 「最初に出てきた status を残し、後から来た重複は無視する」
            // という初期化時のルールになっている。
            //
            // ※ unique の判定は GitHubRepoStatus の Equatable に依存し、
            //    結果として repo.id の一致で重複が判定される。
            .unique(resolve: { _, _ in .ignoreNewOne })

        // (3) trimmed=true の場合は liked のものだけ残す
        // お気に入り一覧など、ユースケースに応じたビューを Domain 側で作れる。
        if trimmed {
            statuses = statuses.filter { $0.isLiked }
        }
    }

    // MARK: - Append / Merge
    //
    // 新しい repos/likes を既存 statuses に “マージ” する。
    // ここでのドメインルールは「新しい情報で上書き（古いものを消す）」。
    mutating func append(repos: [GitHubRepo], likes: [GitHubRepo.ID: Bool]) {

        // (1) 既存 statuses に、新しく生成した statuses を連結する
        // ただしこの時点では重複があり得る（MayNotUnique）。
        let newStatusesMayNotUnique = statuses + Array(repos: repos, likes: likes)

        // (2) unique して repo 重複を解消する
        // ここでは .removeOldOne を選んでいるため、
        // 「重複があった場合は古い方を捨てて新しい方を残す」
        // というマージ戦略になっている。
        //
        // つまり append は “差分更新” というより “最新データの反映”。
        statuses = newStatusesMayNotUnique
            .unique { _, _ in .removeOldOne }
    }

    // MARK: - Update like state
    //
    // 指定 repo.id の isLiked を更新する。
    // List 内に存在しない id の場合はドメインエラーを投げる。
    mutating func set(isLiked: Bool, for id: GitHubRepo.ID) throws {

        // (1) 対象 repo を探す（id一致）
        // firstIndex(where:) を使って、更新対象の index を得る。
        guard let index = statuses.firstIndex(where: { $0.repo.id == id }) else {
            // (2) 見つからなければ domain error
            // “更新しようとしたが対象が存在しない” はドメイン操作の失敗として扱う。
            throw Error.notFoundRepo(ofID: id)
        }

        // (3) 既存 status を取り出し、repo はそのまま、isLiked だけ差し替えた新しい status を作る
        // struct（値型）なので不変性を保ちやすい。
        let currentStatus = statuses[index]
        statuses[index] = GitHubRepoStatus(
            repo: currentStatus.repo,
            isLiked: isLiked
        )
    }

    // MARK: - Query
    //
    // id で status を引けるようにするサブスクリプト。
    // これにより呼び出し側は statuses 配列の走査を意識しにくくなる。
    subscript(id: GitHubRepo.ID) -> GitHubRepoStatus? {
        return statuses.first(where: { $0.repo.id == id })
    }
}

//
// MARK: - Clean Architecture 観点での補足（Entity/ValueObject/Collection）
//
// この構造は “Entity単体” ではなく、以下のように整理すると理解しやすい。
//
// - GitHubRepo: Entity（同一性 = repo.id）
// - GitHubRepoStatus: Entityを包む “ドメイン合成モデル”（Repo + ユーザ状態）
// - GitHubRepoStatusList: コレクションに対するドメインルールを持つ型（Collection / Aggregate的）
//
// 特に List が “重複排除・マージ戦略・更新失敗のエラー” を握っているのは、
// UseCase から見ると「正しい集合操作が保証されたドメインAPI」になるため、設計として価値が高い。
//
// 追加で改善するなら:
// - statuses を Dictionary<ID, Status> にすると検索/更新が O(1) になりやすい
//   （ただし順序が必要なら配列も必要）
// - unique の戦略を List 内で明文化（コメントに加えて命名でも）すると読み手に優しい
//```