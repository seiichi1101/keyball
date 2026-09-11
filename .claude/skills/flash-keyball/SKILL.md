---
name: flash-keyball
description: Keyball のファームウェアを実機に書き込む(焼く)手順。CI アーティファクトの取得、Remap キーマップの事前保存、avrdude による左右両側の書き込み、動作確認まで。「焼いて」「flash して」「ファーム書き込み」「ファーム更新」で使う。
---

# Keyball ファームウェア書き込み

Pro Micro(atmega32u4 / caterina bootloader)搭載の Keyball を対象にする。
`qmk flash` は使わない(理由は末尾の「既知のハマりどころ」)。同梱の `flash.sh` を使う。

## 0. 事前確認 — ここを飛ばさない

1. **設定のバックアップ。** `flash.sh` は書き込みの直前に EEPROM 全体(1024 バイト)を
   `.tmp/eeprom/eeprom-<side>-<timestamp>.bin` へ自動で吸い出す。これで Remap のキー割り当ても
   `KBC_SAVE` で保存した Keyball 設定値(CPI / スクロール除数 / AML / スナップ)も丸ごと残る。
   - バックアップが 1024 バイトで取れたことを出力で確認してから先に進む(失敗したら書き込みも中止される)
   - **ビルド日が前回と違えばキーマップは必ずリセットされる。** 書き込み後に手順 2.5 の復元が要る。
     ユーザーにもその旨を先に伝えておく
   - **同じ EEPROM レイアウトのファーム間でしか復元できない**。レイアウトが変わる場合は下の 2 を参照し、
     Remap 側のクラウド保存や全レイヤーのスクリーンショットも取っておくようユーザーに依頼する
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
# flash.sh <firmware.hex>|--backup-only [side] [wait_seconds]
bash .claude/skills/flash-keyball/flash.sh .tmp/keyball_keyball61_via.hex right
bash .claude/skills/flash-keyball/flash.sh .tmp/keyball_keyball61_via.hex left
```

`side` はバックアップのファイル名に入るだけだが、左右を取り違えると復元時に事故るので必ず渡す。
`--backup-only` は書き込みをせず EEPROM の吸い出しだけ行う(検証やバックアップ目的)。

1. 起動して `Waiting for caterina bootloader` を確認したら、**USB が刺さっている側のリセットボタンを押してもらう**
2. 出力を確認する。3 つそろって成功:
   - `EEPROM backup OK (1024 bytes)`
   - `NNNN bytes of flash verified`(`written` と同じバイト数)
   - `FLASH OK`
3. `lsusb` で `5957:0100` に戻っていることも見る
4. **USB を反対側に差し替えてもらい**、`side` を変えて同じ手順
5. 成功したかは必ず出力で確認して報告する

スクリプトの挙動:
- デバイスが `-w`(書き込み可能)になるまで待つ。存在チェックだけでは udev の ACL 付与に先行してしまう
- EEPROM 読み出しと flash 書き込みを **1 回の avrdude セッション**で行う。プログラマが接続している間 caterina は
  bootloader に留まるので、8 秒の窓の中に両方収まる(リセットは 1 回で済む)
- バックアップが 1024 バイトでなければ `exit 3` で中止する
- `avrdude` は `timeout 40` で囲み、失敗しても抜けずに次のリセットを待つ。初回の avr109 ハンドシェイクが固まることがある(実測で 1 回目タイムアウト → 2 回目成功)
- 待機は既定 570 秒。第 3 引数で変えられる

## 2.5. キーマップの復元 — 日付をまたいでビルドしたら必須

**ビルド日が前回と違うファームを焼くと、Remap のキーマップは必ず標準値にリセットされる。**
ソースが 1 バイトも変わっていなくても起きる。QMK の `via_eeprom_is_valid()` が
`QMK_BUILDDATE` から VIA マジック 3 バイトを作っているため:

```
"2026-09-10" → 26 09 10     "2026-09-11" → 26 09 11
```

マジックが合わないと VIA は EEPROM を無効と判断し、動的キーマップを `keymap.c` で初期化し直す。
EEPROM が消えるわけではない。`keyball_config_t`(CPI / スクロール除数 / AML / スナップ)は
VIA のマジック検査の対象外なので影響を受けない。消えるのはキー割り当てだけ。

**バックアップをそのまま書き戻しても直らない。** 起動のたびにファームが再度リセットする。
バックアップ側のマジックを、走っているファームが書いた値に合わせる必要がある。

```bash
bash .claude/skills/flash-keyball/restore-eeprom.sh .tmp/eeprom/eeprom-left-<timestamp>.bin
```

リセットを 2 回押してもらう(1 回目でファームのマジックを読み、2 回目でパッチ済みを書き戻す)。

- **master 側だけでよい。** split では USB を挿した側(master)だけが動的キーマップを参照する。
  slave 側の EEPROM は使われないので復元不要
- ファームのレイアウトが本当に変わった場合はマジックを合わせても壊れる。
  手順 0-2 のレイアウト差分チェックで弾くこと
- 恒久的に避けたいなら `keymap.c` を実配列に合わせて書いてしまう。リセットされても正しい配列に戻る

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
| 焼いた後 Remap のキーマップが標準に戻る | ビルド日が変わり VIA マジックが不一致(EEPROM は消えていない) | 手順 2.5 の `restore-eeprom.sh` |
| バックアップを書き戻しても戻らない | マジックが古いままなので起動時に再リセットされる | マジックをパッチしてから書く(`restore-eeprom.sh` が行う) |
| 片側だけキーマップが違う | split では master 側の EEPROM しか参照されない。slave 側は古いまま残る | 異常ではない。復元は master 側だけでよい |

## 参考: 実測で確かめた事実

- `avrdude` の `erasing chip` は **EEPROM を消さない**。caterina は flash のみ消去する
  (書き込み前後で `keyball_config_t` が保存されていることを確認済み)
- VIA マジックは `0x25` から 3 バイト。`keyball_config_t` は `EECONFIG_KEYBOARD`(`0x0F` から 4 バイト、LE)
- 動的キーマップは 4 層 × 10 行 × 8 列 × 2 バイト = 640 バイト、キーコードはビッグエンディアン
- `QK_KB_0 = 0x7E00`(EEPROM 上の `SCRL_MO` などから確認)
