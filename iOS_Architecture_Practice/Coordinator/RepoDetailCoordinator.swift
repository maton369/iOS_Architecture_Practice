//
//  RepoDetailCoordinator.swift
//
//  このファイルは Coordinator パターンにおける「Repo 詳細フロー」を担当する Coordinator である。
//  RepoListCoordinator から “Repo が選択された” イベントを受け取った後、
//  選択された Repo を入力（model）として受け取り、詳細画面（RepoDetailViewController）へ遷移する。
//
//  Coordinator パターンの文脈でのポイントは次の通り。
//
//  - ViewController は “どこへ遷移するか” を決めない
//    → VC は表示とユーザ操作の受付に集中し、遷移は Coordinator が統括する
//
//  - Coordinator が “遷移先に必要な入力” を把握して渡す
//    → ここでは model（GitHubRepoModel）を保持し、RepoDetailViewController に repoURL を渡している
//
//  - Navigator（UINavigationController）を注入して push/present を実行する
//    → 遷移の実体は navigator、意思決定は Coordinator にある
//
//  この設計により、画面遷移のロジックが ViewController から切り離され、
//  アプリのフローが Coordinator ツリーとして追跡しやすくなる。
//

import UIKit

// MARK: - RepoDetailCoordinator
//
// Repo 詳細画面を起点とするフロー（または Repo 詳細画面 “そのもの”）を管理する Coordinator。
// RepoListCoordinator の子Coordinatorとして生成され、同じ navigator を使って navigation stack 上で push する。
class RepoDetailCoordinator: Coordinator {

    // MARK: - Navigator

    /// 画面遷移（push/pop）を実行する UINavigationController。
    /// RepoListCoordinator と同じ navigator を共有するため、
    /// 一覧→詳細の遷移は同一ナビゲーションスタック上で自然に行われる。
    let navigator: UINavigationController

    // MARK: - Input (Flow parameter)

    /// 遷移先に渡すための入力データ（選択された Repo）。
    /// Coordinator は “どの画面を開くか” だけでなく
    /// “その画面に何を渡すか” を責務として持つことが多い。
    ///
    /// ここで model を保持しておくことで、
    /// - start() のタイミングで必要な情報を ViewController に注入できる
    /// - 後から追加の入力（例: repoId, title, analytics param）が増えても拡張しやすい
    let model: GitHubRepoModel

    // MARK: - State (Ownership)

    /// 詳細画面の参照。
    /// - Coordinator が画面を所有していることを明確にする
    /// - 必要なら表示中の画面へ追加操作できる（例: refresh 指示）
    ///
    /// ただし、参照を保持すると VC と Coordinator の相互参照が増えうるため、
    /// 実務では “必要になってから持つ” 方針でもよい。
    var repoDetailViewController: RepoDetailViewController?

    // MARK: - Init

    /// navigator と model（入力）を注入して初期化する。
    /// 通常は親Coordinator（RepoListCoordinator）が生成し、遷移元の文脈（選択Repo）を渡す。
    init(navigator: UINavigationController, model: GitHubRepoModel) {
        self.navigator = navigator
        self.model = model
    }

    // MARK: - Start

    /// Repo 詳細フローを開始する。
    ///
    /// アルゴリズム:
    /// 1) RepoDetailViewController を生成
    /// 2) 遷移先が必要とする入力（repoURL）を注入
    /// 3) navigator.pushViewController で詳細画面へ遷移
    /// 4) 参照を保持してフローの所有権を明確化
    ///
    /// ここで注目すべき点は (2) の “入力の注入”。
    /// ViewController は外部から repoURL を渡される前提になっており、
    /// 画面生成側（Coordinator）が DI を担うことで、VC の責務が軽くなる。
    func start() {

        // (1) 詳細画面を生成
        let viewController = RepoDetailViewController()

        // (2) 入力を注入
        // 選択された Repo の URL を詳細画面へ渡す。
        // これにより RepoDetailViewController は
        // “どこから来た repo か” を自分で探さずに済む。
        viewController.repoURL = model.url

        // (3) 画面遷移（push）
        // 同じ navigator を使うため、戻るボタンで一覧に戻れる自然なスタックになる。
        self.navigator.pushViewController(viewController, animated: true)

        // (4) 参照保持
        self.repoDetailViewController = viewController
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) ViewController への依存注入を “プロパティ代入” ではなく init に寄せる
//    - viewController.repoURL = ... は注入漏れが起きやすい（必須値なのに nil のままなど）
//    - 可能なら RepoDetailViewController(repoURL: ...) のような初期化注入が安全
//
// 2) 参照の保持が本当に必要か
//    - 追加操作が不要なら repoDetailViewController を持たない方が循環参照リスクが減る
//
// 3) フロー終了通知（finish）
//    - 詳細画面が閉じたら親Coordinatorへ通知し、repoDetailCoordinator を nil にして解放する設計が定番
//
// 4) Router（遷移先決定）との責務分離
//    - Coordinator が “組み立て” と “遷移” の両方を持つ場合、規模が大きいと肥大化する
//    - 画面生成を Factory に寄せる構成も検討余地がある
//```