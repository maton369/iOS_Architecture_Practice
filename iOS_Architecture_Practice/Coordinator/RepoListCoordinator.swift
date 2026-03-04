//
//  RepoListCoordinator.swift
//
//  このファイルは Coordinator パターンにおける「Repo 一覧フロー」を担当する Coordinator である。
//  Coordinator パターンの狙いは、ViewController から
//   - 画面生成（依存注入）
//   - 画面遷移（push / present）
//   - 画面フローの分岐（次画面へ進む条件）
//  を切り離し、画面フローを Coordinator に集約することにある。
//
//  RepoListCoordinator の責務は次の2つに整理できる。
//
//  1) フロー開始時に RepoListViewController を生成して表示する（start）
//  2) RepoListViewController のイベント（Repo選択）を受け取り、詳細フローへ遷移する
//
//  ここでは delegate を使って
//  「ViewController → Coordinator へイベント通知」
//  を行っており、ViewController が自分で詳細画面を push しない構造になっている。
//  これにより ViewController の責務は
//   - 表示
//   - ユーザ操作の受付
//   - delegate への通知
//  に限定され、遷移ロジックは Coordinator に集約される。
//

import UIKit

// MARK: - RepoListCoordinator
//
// Repo 一覧画面（RepoListViewController）を起点とするフローを管理する Coordinator。
// Navigator（UINavigationController）を注入され、push/pop による遷移を担当する。
class RepoListCoordinator: Coordinator {

    // MARK: - Navigator

    /// 画面遷移を実行する UINavigationController。
    /// Coordinator パターンでは “遷移の実体” を Coordinator が持つことが多い。
    /// これにより ViewController が navigationController を直接触らずに済む。
    let navigator: UINavigationController

    // MARK: - State (Flow ownership)

    /// 一覧画面の参照を保持する。
    /// - 画面に対して追加の操作をしたい場合（例: 再読み込み指示、スクロール制御）に必要になる。
    /// - 単に “表示しただけ” なら保持しなくても動作するが、フロー管理として持っておくと拡張しやすい。
    var repoListViewController: RepoListViewController?

    /// 詳細フローを担当する子Coordinator。
    /// Coordinator は子Coordinatorを strong に保持しないと、
    /// start() 直後に解放されて遷移が壊れる／イベントを受けられない、という事故が起きやすい。
    var repoDetailCoordinator: RepoDetailCoordinator?

    // MARK: - Init

    /// UINavigationController を注入して初期化する。
    /// AppCoordinator など上位Coordinatorが navigator を用意して渡す想定。
    init(navigator: UINavigationController) {
        self.navigator = navigator
    }

    // MARK: - Start

    /// Repo 一覧フローを開始する。
    ///
    /// アルゴリズム:
    /// 1) RepoListViewController を生成
    /// 2) delegate に self をセット（VC → Coordinator へのイベント経路を作る）
    /// 3) navigator.pushViewController で画面遷移
    /// 4) 参照を保持してフローの所有権を明確にする
    ///
    /// ここで重要なのは (2) で、RepoListViewController は
    /// 「選択されたRepoをどう表示するか（次画面へ進むか）」を知らず、
    /// ただ delegate に “選ばれた” ことを通知するだけになる。
    /// この分離により、画面フローの意思決定が Coordinator に集約される。
    func start() {
        let viewController = RepoListViewController()

        // VC → Coordinator の通知経路を作る。
        // これにより VC は push を自分で行わず、Coordinator に “イベント” を伝えるだけになる。
        viewController.delegate = self

        // 一覧画面を表示（push）。
        navigator.pushViewController(viewController, animated: true)

        // 一覧画面の参照を保持。
        // - 表示状態の管理
        // - 追加操作
        // を行いたいときに役立つ。
        self.repoListViewController = viewController
    }
}

// MARK: - RepoListViewControllerDelegate
//
// RepoListViewController 側で Repo が選択されたときに呼ばれる delegate メソッドを実装する。
// ここが「画面フロー分岐の中心」であり、次画面へ遷移する意思決定を Coordinator が行う。
extension RepoListCoordinator: RepoListViewControllerDelegate {

    /// Repo が選択されたことを受け取り、詳細フローへ遷移する。
    ///
    /// アルゴリズム:
    /// 1) RepoDetailCoordinator を生成（必要な依存として navigator と model を注入）
    /// 2) detailCoordinator.start() を呼んで詳細画面へ遷移
    /// 3) 子Coordinator を strong に保持（ライフサイクル管理）
    ///
    /// ここで model（GitHubRepoModel）を RepoDetailCoordinator に渡しているのは、
    /// 「遷移先が必要とする入力」を Coordinator が把握している、という意味になる。
    /// ViewController は “どんな情報を持って遷移するか” まで考えなくてよい。
    func repoListViewControllerDidSelectRepo(_ repo: GitHubRepoModel) {

        // 詳細フローCoordinatorを生成。
        // navigator を共有しているため、同じ NavigationController のスタック上で詳細へ進む。
        let repoDetailCoordinator = RepoDetailCoordinator(
            navigator: self.navigator,
            model: repo
        )

        // 詳細フロー開始（通常は push / present が行われる）。
        repoDetailCoordinator.start()

        // 子Coordinatorを保持して解放を防ぐ。
        self.repoDetailCoordinator = repoDetailCoordinator
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) 子Coordinatorの解放タイミング
//    - 詳細画面から戻ったら repoDetailCoordinator = nil にして解放する
//    - 例えば RepoDetailCoordinator が delegate/closure で “finish” を通知する設計が多い
//
// 2) RepoListViewController の生成を Factory に寄せる
//    - RepoListViewController() 直生成だと依存注入が増えたときに肥大化しやすい
//    - Coordinator が画面組み立てを担う方針なら Factory/Builder を導入すると見通しが良い
//
// 3) Coordinator の “start” の責務を明確にする
//    - “push するだけ” なのか
//    - “初期画面の状態もセットする” のか
//    などをチームで統一すると保守性が上がる
//```