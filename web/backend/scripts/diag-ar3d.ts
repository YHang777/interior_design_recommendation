/**
 * Read-only look at products.ar3d — the 3D-generation ledger the app writes.
 *
 *   npm run diag-ar3d
 *
 * Prints id/name/status/error/attempts/taskId/submittedAt per product that
 * has an ar3d map, newest submission first. Nothing is written.
 */
import { fbDb } from '../src/config/firebase';

interface Row {
  id: string;
  name: string;
  status: string;
  error: string;
  attempts: number;
  taskId: string;
  submittedAt: string;
  url: string;
}

async function main(): Promise<void> {
  const snap = await fbDb().collection('products').get();
  const rows: Row[] = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const a = data.ar3d;
    if (a == null || typeof a !== 'object') continue;
    rows.push({
      id: doc.id,
      name: String(data.name ?? ''),
      status: String(a.status ?? ''),
      error: String(a.error ?? ''),
      attempts: Number(a.attempts ?? 0),
      taskId: String(a.taskId ?? ''),
      submittedAt: String(a.submittedAt ?? ''),
      url: String(a.url ?? ''),
    });
  }
  rows.sort((x, y) => y.submittedAt.localeCompare(x.submittedAt));
  console.log(`products with ar3d: ${rows.length}`);
  for (const r of rows.slice(0, 25)) {
    console.log(JSON.stringify(r));
  }
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
