//
//  GithubAction.swift
//  FluxExample
//
//
//  このファイルは Flux アーキテクチャにおける “Action” を定義している。
//  Action は「アプリ内で何が起きたか」を表すイベント（メッセージ）であり、
//  Dispatcher を通して Store に配信され、Store が State を更新するトリガになる。
//
//  Flux の単方向データフローをもう一度整理すると次の通り。
//
//      View（ユーザ操作）
//           ↓（イベント）
//      ActionCreator（必要なら副作用を実行）
//           ↓（Action を dispatch）
//      Dispatcher（Action を配信）
//           ↓
//      Store（Action を解釈して State を更新）
//           ↓（State 変更通知）
//      View（描画更新）
//
//  つまり Action は “State 更新の入力” であり、Store にとってのインターフェースである。
//
//  Action を enum にする利点:
//  - “起きうるイベントの種類” が列挙される（網羅性が上がる）
//  - Store 側で switch により網羅的に処理できる（コンパイル時に漏れに気付きやすい）
//  - payload（付随データ）を型として持てる
//
//  ただし payload に Optional や Error? を多用すると、
//  “nil の意味” が曖昧になりやすいので、実務では
//  - clear 用の Action を分ける
//  - Error をアプリ独自のエラー型に寄せる
//  - Optional を減らして state 側で表現する
//  といった整理を行うことが多い。
//

import GitHub

// MARK: - Action
//
// Action は “イベントの種類” と “それに伴う値（payload）” の組である。
// Store は Action を受け取り、それに応じて state を更新する。
// View は state を描画するだけで、Action を直接解釈しないのが Flux の基本。
enum Action {

    // MARK: - Search
    //
    // 検索機能に関するイベント群。
    // ここにある Action は、検索画面の State（query, repositories, pagination, loading, editing, error）を構成する。
    // ActionCreator はユーザ入力やAPI結果に応じてこれらを dispatch する。

    /// 検索クエリが変更されたことを表す。
    /// payload が String? なのは、未入力状態やクリアを nil で表現したい意図が考えられる。
    /// ただし nil と ""（空文字）の意味が混ざりやすいので、どちらを使うかを設計で統一すると安全。
    case searchQuery(String?)

    /// ページング情報が更新されたことを表す。
    /// GitHub API のレスポンスに含まれる pagination を Store に保存するために使う。
    /// nil は “まだ未取得” や “ページング不要/終了” などを表しうるので、意味の定義が重要。
    case searchPagination(GitHub.Pagination?)

    /// 検索結果（Repository の配列）が更新されたことを表す。
    /// Store はこの配列を state.repositories に反映し、View はそれをリスト表示する。
    /// “追加読み込み” と “置き換え” のどちらを意図するかは Store 側の実装方針次第。
    case searchRepositories([GitHub.Repository])

    /// 検索結果をクリアする。
    /// payload を持たない Action は “指示” に近い。
    /// Store は repositories を空配列にし、pagination や error 等も必要に応じて初期化する。
    case clearSearchRepositories

    /// 検索中かどうか（ローディング表示）を表す。
    /// ActionCreator は API通信開始時に true、完了時に false を dispatch することで、
    /// UI が spinner 表示を切り替えられる。
    ///
    /// 実務では “並列リクエスト” があり得るため、Bool ではなくカウンタや requestId を使うこともある。
    case isRepositoriesFetching(Bool)

    /// 検索フィールド編集中かどうかを表す。
    /// UI状態も Store に集約する流派では、候補表示やボタン活性制御などに用いる。
    case isSearchFieldEditing(Bool)

    /// エラー状態を表す。
    /// Error? を直接載せる設計は手軽だが、nil の意味（エラー解除/未発生）が曖昧になりがち。
    /// 実務ではアプリ独自の Error 型に寄せたり、error を state で管理し clearError Action を別途用意することが多い。
    case error(Error?)

    // MARK: - Favorite
    //
    // お気に入り機能に関するイベント群。
    // LocalCache 更新後の “正” の配列を Store に反映するために使う。

    /// お気に入り一覧を置き換える。
    /// ActionCreator は LocalCache から取得・更新した配列をそのまま dispatch し、
    /// Store は state.favorites を更新する。
    case setFavoriteRepositories([GitHub.Repository])

    // MARK: - Others
    //
    // 検索/お気に入りに属さない UI状態（選択中アイテムなど）を表すイベント群。

    /// 選択中のリポジトリが変わったことを表す。
    /// nil は “未選択/選択解除” を表す。
    /// Store は state.selectedRepository を更新し、View は詳細表示や遷移のトリガに利用する。
    case selectedRepository(GitHub.Repository?)
}