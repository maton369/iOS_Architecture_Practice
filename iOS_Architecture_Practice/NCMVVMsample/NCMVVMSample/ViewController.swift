//
//  ViewController.swift
//  RxSimpleSample
//
//
//  この ViewController は、RxSwift/Combine を使わずに「リアクティブなUI更新」を
//  NotificationCenter で再現した最小サンプルの View（UI層）である。
//
//  ここで実現しているアルゴリズム（データフロー）は次の通り。
//
//    1) ユーザが TextField に入力する（editingChanged）
//    2) ViewController が現在の id/password をまとめて ViewModel に渡す
//    3) ViewModel が入力を検証し、結果を Notification として発火する
//    4) ViewController が通知を購読して UILabel の text / textColor を更新する
//
//  つまり、入力→検証→出力 の単方向フローが成立している。
//  Rx/Combine の用語で言えば、
//    - TextField の入力が “ストリーム”
//    - ViewModel が “変換（map/validate）”
//    - Label 更新が “購読（subscribe）”
//  に相当する。
//  ただし NotificationCenter を使うため、型安全性や購読解除は手動管理になりやすい点が注意点である。
//

import UIKit

// MARK: - View (UIViewController)
//
// final: 継承による挙動変更を防ぎ、サンプルの意図を固定する。
// ViewController の責務は次の2つに限定されるのが理想。
//  (1) Input: UIイベントを受け取って ViewModel に渡す
//  (2) Output: ViewModel の出力イベントを購読して UI を更新する
final class ViewController: UIViewController {

    // MARK: UI Outlets

    /// ユーザID入力欄。
    /// 文字が変わるたびに .editingChanged イベントが発火し、ViewModel の再評価が走る。
    @IBOutlet private weak var idTextField: UITextField!

    /// パスワード入力欄。
    /// こちらも同様に .editingChanged を拾い、常に最新の入力状態で検証する。
    @IBOutlet private weak var passwordTextField: UITextField!

    /// 検証結果（OK/エラーメッセージ）を表示するラベル。
    /// text と textColor は ViewModel の通知に応じて更新される。
    @IBOutlet private weak var validationLabel: UILabel!

    // MARK: Event Bus (NotificationCenter)

    /// この画面内でのみ使う NotificationCenter。
    /// NotificationCenter.default ではなくローカルインスタンスを使うことで、
    /// 通知のスコープを “この画面 + この ViewModel” に閉じる意図がある。
    ///
    /// 注意:
    /// - selector型 addObserver を使う場合、基本は removeObserver が必要になることが多い
    /// - 大規模では Combine/Rx でストリーム化した方が管理が楽になる
    private let notificationCenter = NotificationCenter()

    // MARK: ViewModel

    /// ViewModel は入力（id/password）を受け、検証結果を通知で出す。
    /// ここでは notificationCenter を注入して共有し、同じバスで publish/subscribe する。
    ///
    /// lazy にしている理由:
    /// - notificationCenter が初期化された後に ViewModel を生成する
    /// - viewDidLoad で必ず使うので実質的には即生成と同等
    private lazy var viewModel = ViewModel(
        notificationCenter: notificationCenter
    )

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // --- Input wiring: TextField -> ViewController ---
        // どちらの TextField が変化しても同じハンドラに集約し、
        // “画面全体の入力状態” を ViewModel に渡して再評価する。
        //
        // これにより、片方だけ更新して状態がズレる事故を避けやすい。
        idTextField.addTarget(
            self,
            action: #selector(textFieldEditingChanged),
            for: .editingChanged
        )
        passwordTextField.addTarget(
            self,
            action: #selector(textFieldEditingChanged),
            for: .editingChanged
        )

        // --- Output wiring: ViewModel -> NotificationCenter -> ViewController ---
        // ViewModel が発火する通知を購読し、UILabel を更新する。
        //
        // ここで購読しているイベントは2つ。
        // - changeText  : ラベルの文言更新
        // - changeColor : ラベルの色更新
        //
        // Rx/Combine なら label.text と label.textColor へ bind する箇所に相当する。
        notificationCenter.addObserver(
            self,
            selector: #selector(updateValidationText),
            name: viewModel.changeText,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(updateValidationColor),
            name: viewModel.changeColor,
            object: nil
        )

        // 実務的補足:
        // - viewDidLoad で observer 登録した場合、deinit で解除するのが安全。
        //   このサンプルでは deinit が無いので、次のように入れると事故が減る。
        //
        // deinit {
        //     notificationCenter.removeObserver(self)
        // }
        //
        // また、画面の表示/非表示で購読を切り替えるなら viewWillAppear/viewWillDisappear で管理する。
    }
}

// MARK: - Input/Output handlers
//
// 入力処理（UI -> ViewModel）と、出力適用（通知 -> UI）を extension に切り出して見通しを良くしている。
extension ViewController {

    // MARK: Input (UI events)

    /// TextField の文字が変わったときに呼ばれる。
    ///
    /// sender は “どちらの TextField か” を表すが、このサンプルのアルゴリズムでは
    /// 重要なのは “現在の id と password の組” であるため、
    /// 両方の text をまとめて ViewModel に渡して再評価する。
    ///
    /// アルゴリズム:
    /// 1) idTextField.text / passwordTextField.text を取得（Optional）
    /// 2) ViewModel.idPasswordChanged に入力として渡す
    /// 3) ViewModel が検証し、通知(changeText/changeColor)を発火
    @objc func textFieldEditingChanged(sender: UITextField) {
        viewModel.idPasswordChanged(
            id: idTextField.text,
            password: passwordTextField.text
        )
    }

    // MARK: Output (Notification -> UI)

    /// 検証結果テキストの更新通知を受け取って UILabel.text に反映する。
    ///
    /// 設計上の契約:
    /// - ViewModel は Notification.object に String を載せて送る
    /// - ViewController はそれを String として解釈する
    ///
    /// 型安全ではないため、cast に失敗すると UI が更新されない（guard return）。
    /// 実務では userInfo + key 定数化、あるいは Combine/Rx への移行が望ましい。
    @objc func updateValidationText(notification: Notification) {
        guard let text = notification.object as? String else { return }
        validationLabel.text = text
    }

    /// 検証結果色の更新通知を受け取って UILabel.textColor に反映する。
    ///
    /// 契約:
    /// - ViewModel は Notification.object に UIColor を載せて送る
    /// - ViewController は UIColor として解釈する
    @objc func updateValidationColor(notification: Notification) {
        guard let color = notification.object as? UIColor else { return }
        validationLabel.textColor = color
    }
}

// MARK: - 追加の実務向け注意（設計の落とし穴）
//
// 1) 二重登録の危険
//    viewDidLoad が複数回呼ばれることは通常ないが、再生成や別の経路で observer を追加すると
//    同じ通知に複数回反応する可能性がある。
//    → 購読管理を集中させる（deinitで解除、またはトークン保持）
//
// 2) NotificationCenter は型安全でない
//    text と color の payload が Any になるため、契約違反は実行時まで検出できない。
//    → 状態を1つにまとめる/型付きストリームにするのが理想
//
// 3) UI更新は main thread 前提
//    このサンプルは入力がメインから来るので大丈夫だが、将来 ViewModel が非同期化すると
//    通知が別スレッドで届く可能性がある。
//    → UI更新前に main thread を保証する（どちらの層が保証するかを決める）