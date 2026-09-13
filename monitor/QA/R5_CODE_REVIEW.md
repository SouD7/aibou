# R5 コード担当の独立レビュー

担当: `r5_code_review`。22:42:42 JSTの固定対象を新しいコンテキストで確認。返却本文を親が要約して保存。

**COMMENT。新規: CRITICAL 0 / HIGH 0 / MEDIUM 1 / LOW 0。**

## MEDIUM: 単独利用の案内とCPU継続判定

README.md:15は新しいObservationSnapshotを順番にDiagnosticEngine.ingestへ渡す方法を案内する。一方、MonitoringEngine.collectObservations（Sources/MonitorStore.swift:14–17）は既定のstate=snapshotを返し（Sources/Observations.swift:156–160）、ingestはrunning以外で記録をリセットする（Sources/Diagnostics.swift:66–68）。この組み合わせではCPU全体・同一コアの継続判定は20秒後もobservingとなる。

Tests/DiagnosticTests.swift:74–80も、snapshot反復では継続を成立させない契約を固定する。これは意図的なone-shot保護であり、**Store/UI経由には影響しない**。

最小修正は文書をMonitorStore経由へ明確に案内すること。単独での継続利用も提供するなら、stable segmentと採取時刻・開始停止を管理する専用session APIを用意する。snapshotに無条件で継続性を認める修正は推奨しない。確度は高。

## 確認範囲と検証

70ケース・自動8ケース、文書ID、欠損・古さ・未来時刻・区間・20秒継続、UIチェック保持、追加永続化なしを確認。親の独立cacheでの全テスト成功を照合。初回共有cacheでのコンパイル失敗は同一ソース・独立cacheで再現しなかったため、コード問題に含めていない。

R4既知の機器cache時刻MEDIUM、archive整合性LOW、sleep競合・MainActor負荷等WATCHは新規件数に含めない。詳細と親の最終build結果は[統合レビュー](CODE_REVIEW_R5_2026-09-13.md)を参照。
