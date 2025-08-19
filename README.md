# Clinical Trials Data Analysis Bot

AACT（Aggregate Analysis of ClinicalTrials.gov）データベースを活用した臨床試験データ分析用のShinyアプリケーションです。Azure OpenAI を優先し、次に AWS Bedrock（Claude）、最後に Gemini を利用します。

## 🚀 主要機能

### 📊 データ分析機能
- **自然言語クエリ**: 日本語/英語での質問からSQL自動生成
- **リアルタイム実行**: SQLクエリの即座実行と結果表示
- **データ可視化**: ggplot2を使用した高品質なグラフ生成
- **ストリーミング表示**: AIの応答をリアルタイムで表示

### 🏥 臨床試験専門分析
- **スポンサー分析**: 製薬企業別の試験動向
- **適応症戦略**: 競合他社の開発パイプライン分析
- **サイト選定**: 地域別症例集積性分析
- **規制動向**: 承認タイムラインと成功率分析

### 🔒 セキュリティ
- 環境変数による認証情報管理
- ローカルファイルアクセス防止
- SQLインジェクション対策
- 安全なクエリ実行環境

## 📋 前提条件

### 必須環境変数
```bash
# Azure OpenAI（優先）
AZURE_OPENAI_ENDPOINT=https://your-resource-name.openai.azure.com
AZURE_OPENAI_API_KEY=your_azure_openai_api_key_here
AZURE_OPENAI_DEPLOYMENT=gpt-4o-mini
AZURE_OPENAI_API_VERSION=2024-06-01

# AWS Bedrock（次優先）
# 例: anthropic.claude-3-7-sonnet-20250219-v1:0 / anthropic.claude-3-5-sonnet-20240620-v1:0
BEDROCK_MODEL=anthropic.claude-3-5-sonnet-20240620-v1:0
AWS_PROFILE=default
# 必要に応じて
# AWS_ACCESS_KEY_ID=...
# AWS_SECRET_ACCESS_KEY=...
# AWS_SESSION_TOKEN=...
# AWS_DEFAULT_REGION=ap-northeast-1

# （最終）Gemini フォールバック
GEMINI_API_KEY=your_gemini_api_key_here
```

### AACT データベース認証
`.env` ファイルに以下の情報を設定：
```env
AACT_HOST=your_aact_host
AACT_PORT=5432
AACT_DATABASE=aact
AACT_USERNAME=your_username
AACT_PASSWORD=your_password
```

## 🏃‍♂️ 起動方法

### RStudio使用
1. RStudioでプロジェクトフォルダを開く
2. `ui.R`を開き、「Run App」をクリック

### Rコンソール使用
```r
# ワーキングディレクトリを設定
setwd("path/to/databot/app")

# 必要なパッケージをインストール（初回のみ）
install.packages(c("shiny", "DBI", "RPostgres", "dplyr", "ggplot2", "ellmer"))

# アプリを起動
shiny::runApp(".")
```

## 📁 プロジェクト構成

```
app/
├── 📄 ui.R                    # ユーザーインターフェース
├── 📄 server.R                # サーバーロジック  
├── 📄 global.R                # グローバル設定
├── 📄 .env                    # データベース認証情報
├── 📂 functions/              # 機能モジュール
│   ├── chat_bot.R            # Azure OpenAI → Bedrock → Gemini の優先順チャットボット
│   ├── core.R                # R実行エンジン
│   ├── database.R            # AACT DB接続管理
│   ├── utilities.R           # ユーティリティ関数
│   ├── server_helpers.R      # サーバーヘルパー
│   ├── config.R              # 設定管理
│   └── prompt.R              # プロンプト管理
└── 📂 inst/                  # 静的ファイル
    ├── 📂 prompt/
    │   └── prompt.md         # AI指示プロンプト
    └── 📂 www/
        └── style.css         # CSSスタイル
```

## 🎯 使用例

### 基本的な分析
```
"スポンサー別の試験数を教えて"
"フェーズ3の糖尿病試験を分析して"
"日本で実施中の臨床試験の状況は？"
```

### 競合分析
```
"Pfizerが開発中の適応症を調べて"
"がん領域の競合状況を可視化して"
"アジアでの症例集積実績を比較して"
```

### サイト選定分析
```
"糖尿病試験で最も症例集積が早い都市は？"
"腫瘍学試験の施設別実績を分析して"
"希少疾患での地域別募集状況は？"
```

## 🛠️ 技術スタック

- **フロントエンド**: Shiny (R)
- **AI**: Azure OpenAI（優先）→ AWS Bedrock（Claude）→ Gemini（フォールバック）
- **データベース**: PostgreSQL (AACT)
- **可視化**: ggplot2
- **認証**: 環境変数 + .env
- **リアルタイム**: Server-Sent Events

## 📊 データソース

**AACT Database**: ClinicalTrials.gov の包括的な臨床試験データベース
- 40万件以上の臨床試験データ
- 試験デザイン、適応症、スポンサー情報
- 施設、患者募集、結果データ
- 毎日更新される最新情報

## ⚠️ 注意事項

- Azure OpenAI 資格情報の設定が推奨（未設定時は Bedrock、ついで Gemini を利用）
- AACT データベースアクセス権限が必要
- `.env` ファイルの機密情報管理に注意
- 大容量クエリ実行時のパフォーマンス考慮

## 🆘 トラブルシューティング

### データベース接続エラー
1. `.env` ファイルの認証情報を確認
2. ネットワーク接続状況をチェック
3. AACT サーバーの稼働状況を確認

### APIエラー
1. `AZURE_OPENAI_*` 環境変数（endpoint, api key, deployment, api version）の設定確認（未設定なら `GEMINI_API_KEY`）
2. APIキーの有効性チェック
3. API利用制限の確認

---

**開発**: Clinical Trial Data Analysis System  
**更新**: 2025年8月7日
