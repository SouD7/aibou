# R4 設計担当の独立レビュー

担当: `r4_architecture_review`。返却本文から親が要約して保存。対象は2026-09-13 22:14:37 JSTの固定コピー。

**Architectural Status: WATCH。新規BLOCKなし。** 現行単一Store/直列queue、通常のgenerationとsegment、直接command終了待機、atomic保存の契約は整合する。

## 確定指摘との照合

- **MEDIUM: キャッシュの取得時刻。** DeviceSampler.swift:45–83、267–276。Cacheの日付が返却されず、status/panelに毎回nowを付ける。親の動的再現と一致。取得日時を伝播する。TTLもDate差なので時計後退時に期限が延びることが分岐上成立する。TTLは単調時計、表示取得日時はDateへ分けることを推奨。時計変更の実機試験は未実施。
- **LOW: 保存summaryの整合性。** StorageScanner.swift:246–260。graphの検証だけでは完了日時・件数・合計の矛盾を排除できず、親fixtureでsavedとして受理した。検証済みnodes/rootから件数と合計を再構成し、完了日時等を検証することを推奨。正常writerの破損生成や外部入力経路は確認していない。

## 新規WATCH 1: スリープ復帰時のclock baseline競合

固定対象のMonitorStore.swift:152–176、197–224では、willSleepでgenerationを失効させても、sampling queueのblockは開始前にgenerationを検査しない。MainActorへの結果採用時だけ拒否する。CoreSampler.swift:144–179は結果採否に関係なくpreviousClockを更新する。

成立し得る順序:

1. sleep直前にsampleをqueueへ投入。
2. willSleepで世代が失効するがsampleは未開始。
3. その古いsampleがwake後に実行され、previousClockをwake後時刻へ進める。
4. didWakeのreset(preservingClock: true)がその後に実行され、wake後の基準を保持。
5. 次の採用sampleはsleep前の基準を失い、sleepGapに実際のスリープ時間が入らない。

通常UI採用・履歴segmentはguardで保護され、影響は時計指標に限られる。コード上の順序は成立するが、実スリープ・queue遅延の動的再現は未実施。**実機発生の確度は中としてWATCH**。収集開始前にもthread-safeな世代取消tokenを検査し、基準変更を同じ所有境界で管理する修正を推奨。

## 新規WATCH 2: 診断のための全量Observation投影

固定対象のMonitorStore.swift:197–215で、各基本sampleを採用するたびにMainActor上でobservationSnapshot全体を作って診断へ渡す。Observations.swift:156–209は全panel rowとprocessを変換し、追加電力は最大12,000 leafを保持し得る。

診断は少数の集計指標を使うが、全process/nettop/powermetrics行を1〜2秒ごとに再投影する経路となる。**GUI遅延・最大入力時の性能は未測定で、確定性能不具合とはしない。** collection metadataと必要な集計指標だけを診断入力にすることを推奨。診断追加は開発途中であり、未完成という理由では指摘に数えない。

## 維持する既知WATCH

- 管理者認証先のpowermetrics終了は未確認。直接osascript停止のfixtureで子の消滅は証明できない。
- 全件JSON・全件索引のメモリ負荷。過去の50万nodeの最大RSS約948.75 MBは今回の再測定ではない。
- terminal scanのUI索引が完成するまで保存groupへ登録されず、途中終了時は新結果が保存されない。
- MainActor上で履歴を同期decode/sanitizeする負荷。
- 将来、直接Engineを複数consumerで使う場合の所有境界。現行private engine/serial queueでは未発生。

## 検証

既存全テスト成功（22:17:47 JST）と2件の動的再現を照合。返却時には固定コピーのbuildが進行中だったが、その後親が最適化warnings-as-errors build、codesign strict、plist/privacy lint成功を確認した。[統合報告](CODE_REVIEW_R4_2026-09-13.md)参照。

管理者認証・GUI・実スリープ・巨大archive・ユーザー保存データの操作は行っていない。22:14:37以降の並行変更は今回の対象外。
