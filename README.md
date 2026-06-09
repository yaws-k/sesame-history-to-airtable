# Sesame History to Airtable

セサミ（スマートロック）の履歴をAirtableに転送するスクリプトです。

- セサミ <https://jp.candyhouse.co/>
- Airtable <https://airtable.com/>

GitHub Actionsで夜中に自動実行し、1日分をまとめて転送しています。  
なお、APIを無駄にしないようにしつつ取りこぼしも防ぐため、Airtableに保存されている最新の履歴情報を取得し、それより新しい履歴をセサミから取得します。

## 事前準備

### セサミ

[Sesame Biz](https://biz.candyhouse.co/)の「開発者向け」ページから、APIキーとデバイスUUIDを取得してください。  
（ログインにはあらかじめアプリ側でメールアドレスを登録しておく必要があります。）

### Airtable

### テーブル

Airtableでベースとテーブルを作成してください。テーブルには以下のフィールドを作成してください。  
（上3つは必須。ただ、raw dataだけだと見ても分かりにくいので、下2つのフィールドも追加しておくことを推奨。）

- `raw timestamp` number（ユニークキー）
- `raw type` number
- `history tag` single line text
- `timestamp` formula: `DATETIME_PARSE({raw timestamp})`
- `type` formula（下記）

```text
SWITCH(
  {raw type},
  1, "施錠 (BLE)",
  2, "解錠 (BLE)",
  3, "内部時計校正",
  4, "オートロック設定変更",
  5, "施解錠角度設定変更",
  6, "オートロック",
  7, "施錠（手動）",
  8, "解錠（手動）",
  9, "手動操作",
  10, "モーター施錠完了",
  11, "モーター解錠完了",
  12, "施解錠失敗",
  14, "施錠（WiFiモジュール）",
  15, "解錠（WiFiモジュール）",
  16, "施錠 (Web API)",
  17, "解錠 (Web API)",
  90, "ドア開（センサー）",
  91, "ドア閉（センサー）",
  "未知の操作"
)
```

ビューでは`raw type`を隠し、`raw timestamp`の降順でソートすると見やすいと思います。

### API関連情報

AirtableのURLから、ベースIDとテーブルIDを取得してください。

`https://airtable.com/appAAAAAA/tblBBBBB/viwCCCCCC?blocks=hide`

- ベースID: `appAAAAAA`
- テーブルID: `tblBBBBB`

[Builder HubのPersonal access tokensメニュー](https://airtable.com/create/tokens)から、`data.records:read`と`data.records:write`の権限を持つPATを作成してください。

## 処理実行

### 環境変数の設定

利用する環境変数は以下のとおりです。

```env
SESAME_API_KEY=APIキー
SESAME_UUID=デバイスUUID

AIRTABLE_PAT=AirtableのPAT
AIRTABLE_BASE_ID=AirtableのベースID
AIRTABLE_TABLE_ID=AirtableのテーブルID
```

GitHubリポジトリのSettings > Secrets and variables > Actionsから、上記の環境変数をSecretsとして追加してください。

ローカル環境で実行する場合は、`.env`ファイルを作成して上記の内容を記述してください。

### 実行

GitHub Actionsの設定ファイルもすでにあるので、自分の実行したい時間に修正してお使いください。

## 注意点

- すでに大量（500件以上）の履歴がある場合、初回はセーフティロックに引っかかります。スクリプトを修正して対応してください。
- SesameもAirtableもAPIのレートリミットや使用回数の上限があります。制限に引っかかってしまった場合は、上位プランの利用をご検討ください。

## ライセンス

[MIT License](LICENSE)
