# d-harness-plugin

Claude Code 向けミニマムハーネスエンジニアリングプラグイン。

TypeScript・Python プロジェクトに対して3つのフィードバックループを設定し、AIエージェントが自律的に高品質なコードを生成できる環境を構築します。

## ハーネスの構成

| Hook | タイミング | 役割 |
|------|-----------|------|
| **Quality Loop** | PostToolUse | ファイル編集後に自動リント → エラーをエージェントへ即時フィードバック |
| **Safety Gate** | PreToolUse | `.env` や危険なコマンドをブロック |
| **Completion Gate** | Stop | テスト通過を完了条件として強制 |

## インストール

### 前提ツール

| ツール | 用途 | インストール |
|-------|------|------------|
| `jq` | JSON パース | `apt install jq` / `brew install jq` |
| `biome` | TypeScript linter/formatter | `npm install -g @biomejs/biome` |
| `ruff` | Python linter/formatter | `pip install ruff` |
| `pytest` | Python テスト | `pip install pytest` |

TypeScript のみのプロジェクトなら `ruff`/`pytest` は不要、Python のみなら `biome` は不要です。

### プラグインとしてインストール（推奨）

```bash
# ユーザー全体に適用（全プロジェクトで有効）
claude plugin install https://github.com/kama2vern/d-harness-plugin --scope user

# 特定プロジェクトにのみ適用
claude plugin install https://github.com/kama2vern/d-harness-plugin --scope project

# ローカル開発中のプラグインをテスト
claude plugin install /path/to/d-harness-plugin --scope local
```

インストール後、**Claude Code を再起動**してください。

### 手動インストール（レガシー）

プラグインシステムが使用できない環境向け：

```bash
git clone https://github.com/kama2vern/d-harness-plugin
cd d-harness-plugin
bash install.sh
```

オプション：

```bash
# インストール先を変更
bash install.sh --target-dir /path/to/dir

# settings.json のパスを変更（プロジェクトローカル設定など）
bash install.sh --settings /path/to/project/.claude/settings.json

# ドライラン（ファイルを変更せず確認のみ）
bash install.sh --dry-run
```

## プロジェクト構造

```
d-harness-plugin/
├── .claude-plugin/
│   └── plugin.json          # プラグインマニフェスト
├── hooks/
│   ├── hooks.json           # フック設定（${CLAUDE_PLUGIN_ROOT} 参照）
│   ├── post_edit_lint.sh    # Quality Loop
│   ├── pre_safety_gate.sh   # Safety Gate
│   └── stop_test_gate.sh    # Completion Gate
├── settings.json            # プラグイン有効時のデフォルト設定
└── install.sh               # 手動インストーラ（レガシー）
```

## 動作の詳細

### Quality Loop（post_edit_lint.sh）

`.ts` / `.tsx` / `.js` ファイルを編集すると Biome が自動実行されます。
`.py` ファイルを編集すると Ruff が自動実行されます。

1. まず自動修正（`--write` / `--fix`）を試みます
2. 修正後も残存するエラーがあれば、`additionalContext` としてエージェントに注入
3. エージェントは次のターンで自動的に修正を試みます

### Safety Gate（pre_safety_gate.sh）

以下の操作は **構造的にブロック**されます（プロンプトで上書き不可）：

- `.env` / `.envrc` / `.env.*` ファイルの編集
- `secret` / `credential` / `private_key` を含む名前のファイルの編集
- `.pem` / `.key` / `.p12` などの証明書ファイルの編集
- `rm -rf /` や `sudo rm -rf` などの危険なコマンド
- `curl ... | bash` 形式のコマンド（サプライチェーン攻撃対策）

### Completion Gate（stop_test_gate.sh）

Claude Code がタスク完了しようとする際（Stop イベント）、テストを自動実行します：

- `package.json` に `test` スクリプトがあれば `npm test` を実行
- `pytest.ini` / `pyproject.toml` があれば `pytest` を実行
- テストが失敗した場合、エラーを注入してエージェントに修正を続けさせます
- テストが存在しない場合はスキップ

## ライセンス

MIT
