---
name: flash-keyball
description: Keyball のファームウェアを実機に書き込む(焼く)手順。CI アーティファクトの取得、Remap キーマップの事前保存、avrdude による左右両側の書き込み、動作確認まで。「焼いて」「flash して」「ファーム書き込み」「ファーム更新」で使う。
---

# Keyball ファームウェア書き込み

Pro Micro(atmega32u4 / caterina bootloader)搭載の Keyball を対象にする。
`qmk flash` は使わない(理由は末尾の「既知のハマりどころ」)。同梱の `flash.sh` を使う。

## 0. 事前確認 — ここを飛ばさない

1. **Remap のキーマップを保存したかユーザーに確認する。確認が取れるまで書き込みに進まない。**
   - Remap 上でクラウド保存(Save)、または全レイヤーのスクリーンショット
   - 通常の書き込みで EEPROM は消えないが、書き込み失敗時の `EE_CLR` や VIA のキャッシュ不整合で消えることがあり、飛ぶと全レイヤー再入力になる
2. 今回のファームで **EEPROM レイアウトが変わっていないか**を diff で確認する。変わっていたらキーマップは確実に消えるので、その旨を明示してから進める。
   - `DYNAMIC_KEYMAP_LAYER_COUNT`(未定義 = VIA デフォルト 4)
   - `MATRIX_ROWS` / `MATRIX_COLS`(`keyball61/config.h`)
   - `keyball_config_t` のビットフィールド(`lib/keyball/keyball.h`)。`keyball_t` は RAM 側なので変えても影響なし
3. ツールと接続:
   ```bash
   which avrdude                       # 必須
   ls /etc/udev/rules.d/50-qmk.rules   # caterina の uaccess ルール(qmk setup が配置)
   lsusb | grep 5957:0100              # Yowkees Keyball61 が通常モードで見えていること
   ```

## 1. ファームウェアの取得

CI(`Build all firmwares`)のアーティファクトから取る。ローカルには QMK コアが無いのでビルドはしない。

```bash
gh run list --repo <owner>/keyball --branch <branch> --limit 3
gh run download <run-id> --repo <owner>/keyball -n keyball61-via-firmware -D .tmp
ls -l .tmp/*.hex
```

- `<owner>` は fork(`git remote -v` の `origin`)。`gh` のデフォルトが upstream を向くことがあるので `--repo` を必ず付ける
- アーティファクト名は `<keyboard>-<keymap>-firmware`
- **このリポジトリは public。** hex と EEPROM ダンプは `.tmp/`(gitignore 済み)から出さない。EEPROM ダンプは個人のキーマップと設定がそのまま入っているのでコミットしない
- 左右とも**同じ hex** で良い(左右判定は `SPLIT_HAND_MATRIX_GRID` で基板側が行う)

## 2. 書き込み(左右 2 回)

書き込みはユーザーの物理操作(リセットボタン)を伴うので、スクリプトをバックグラウンドで起動してから押してもらう。

```bash
bash .claude/skills/flash-keyball/flash.sh .tmp/keyball_keyball61_via.hex
```

1. 起動して `Waiting for caterina bootloader` を確認したら、**USB が刺さっている側のリセットボタンを押してもらう**
2. 出力に `FLASH OK` と `NNNN bytes of flash verified` が出たら成功。`lsusb` で `5957:0100` に戻っていることも見る
3. **USB を反対側に差し替えてもらい**、スクリプトを再起動して同じ手順
4. 成功したかは必ず出力で確認して報告する。`written` と `verified` のバイト数が一致していること

スクリプトの挙動:
- デバイスが `-w`(書き込み可能)になるまで待つ。存在チェックだけでは udev の ACL 付与に先行してしまう
- `avrdude` は `timeout 25` で囲み、失敗しても抜けずに次のリセットを待つ。初回の avr109 ハンドシェイクが固まることがある(実測で 1 回目タイムアウト → 2 回目成功)
- 待機は既定 570 秒。第 2 引数で変えられる

## 3. 動作確認

- `lsusb` で `Yowkees Keyball61` が見える
- Remap を開いてキーマップが残っている
- 今回変えた機能を実機で確認(例: AML なら「ボールを転がして layer に入る / 動かし続けて留まる / 止めて戻る」)

## 既知のハマりどころ

| 症状 | 原因 | 対処 |
|---|---|---|
| `qmk flash` が `Caterina bootloader was found but is not writable` | `/dev/ttyACM0` 出現直後、udev の `uaccess` ACL が付く前に権限判定してリトライしない | `flash.sh` を使う。恒久対処は `sudo usermod -aG dialout <user>` + 再ログイン |
| `qmk flash: invalid choice` | QMK コア未セットアップ(`qmk_firmware/` に `keyboards/` しか無い) | `flash.sh` は `avrdude` 直叩きなので不要。`qmk setup` は数 GB かかる |
| bootloader 検知後 `avrdude` が無出力で固まる | avr109 同期待ちのハング。その間に 8 秒の bootloader 窓が閉じる | `timeout` + リトライ(スクリプトで対応済み) |
| リセットを押しても検知しない | スクリプトが起動していない(実行権限落ち等) | `bash flash.sh` で起動し、`Waiting...` の表示を確認してから押してもらう |
| `pkill -f avrdude` で自分のシェルが死ぬ | パターンが自分のコマンド行にマッチ | `ps -eo pid,args \| grep "[a]vrdude"` の形で確認・kill する |
| `sudo` が必要な操作 | Claude からはパスワード入力不可 | ユーザーに `! sudo ...` で実行してもらう |
