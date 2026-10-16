# 日本語・英語の表示

画面の文言は `Resources/ja.lproj/Localizable.strings` と
`Resources/en.lproj/Localizable.strings` で管理します。macOSの言語設定に従い、
未対応の言語では英語にフォールバックします。言語を変更した場合やアプリを
再ビルドした場合は、アプリを終了して開き直してください。

Swiftでは `L10n.text` を通して表示します。動的な文章は、語順を翻訳側で変えられる
ように書式文字列を使います。読み上げ用ラベル、状態表示、確認ダイアログも対象です。
GNUbgの診断メッセージはログへ残し、画面には日本語・英語のエラーを表示します。

## 用語

| 英語 | 日本語 | 使い方 |
| --- | --- | --- |
| Ivory / Charcoal | 白 / 黒 | プレイヤーの識別 |
| Match / Game | マッチ / ゲーム | ポイント制の対局全体 / その中の1ゲーム |
| Point | ポイント | 盤面の座標、マッチの得点 |
| Bar / Off | バー / 上がり | ヒットされた駒 / ベアオフした駒 |
| Hint | ヒント | エンジンが提案する手 |
| Cube / Double | キューブ / ダブル | 倍率を示すキューブ / 倍率を上げる申し出 |
| Take / Drop | テイク / ドロップ | ダブルを受ける / ダブルを断ってゲームを終了 |
| Resign | 投了 | 敗北を申し出る操作 |
| Gammon / Backgammon | ギャモン / バックギャモン | 勝敗の種類 |
| Crawford | クロフォード | クロフォードルールが適用されるゲーム |
| Evaluate / Rollout | 通常評価 / ロールアウト | 評価関数での評価 / 試行による解析 |
| Equity / Standard error | 評価値（エクイティ）/ 標準誤差 | 解析結果の値 / 試行による推定誤差 |

ギャモン勝率は、GNUbgの出力に合わせてバックギャモン勝ちを含むため、
日本語では「ギャモン以上の勝率」と表示します。

## 確認

ビルドすると両言語のリソースが `.app` に同梱されます。
`--localization-smoke` はキーの一致・書式引数・動的表示・読み上げラベルを確認します。
`--model-smoke` は選択言語で対局・解析・キャンセル後の復帰を確認します。

```sh
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --localization-smoke --expect-language ja -AppleLanguages '(ja)'
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --localization-smoke --expect-language en -AppleLanguages '(en)'
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --localization-smoke --expect-language en -AppleLanguages '(fr)'
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --model-smoke -AppleLanguages '(ja)'
```

日本語の折り返しや文字切れ、実際の読み上げはGUIでの確認が必要です。
操作の変更に関する要望は、リポジトリ直下の `要望.txt` を確認して進めます。
