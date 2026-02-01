# WKG (WebAssembly Package Manager) のインストール

このプロジェクトでは [WKG](https://github.com/bytecodealliance/wkg) (WebAssembly Package Manager) を使用して、WIT (WebAssembly Interface Types) ファイルを管理します。

## インストール方法

### macOS / Linux (Homebrew)

```bash
brew install bytecodealliance/wasmtime/wkg
```

### Linux (Cargo)

```bash
cargo install wkg
```

### バイナリダウンロード

[GitHub Releases](https://github.com/bytecodealliance/wkg/releases) から最新版をダウンロードしてください。

```bash
# Linux/macOS の例
wget https://github.com/bytecodealliance/wkg/releases/latest/download/wkg-x86_64-unknown-linux-gnu.tar.gz
tar xzf wkg-x86_64-unknown-linux-gnu.tar.gz
sudo mv wkg /usr/local/bin/
```

## 設定

wa.dev レジストリを使用する場合は、以下の環境変数を設定してください：

```bash
export WKG_REGISTRY_URL=https://wa.dev
```

## 使用方法

### WIT ファイルの取得

```bash
wkg wit fetch wasi:http@0.2.0 -o wit/deps
```

### 依存関係の確認

```bash
wkg wit list
```

## 関連リンク

- [WKG GitHub Repository](https://github.com/bytecodealliance/wkg)
- [WebAssembly Component Model](https://component-model.bytecodealliance.org/)
- [wa.dev Registry](https://wa.dev)
