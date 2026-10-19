import { jsPDF } from 'jspdf';
import type { AdminOrderDetail } from '../api/types';

// A4 in points at 72dpi, margin parity with the Flutter invoice (40).
const PAGE_W = 595.28;
const PAGE_H = 841.89;
const MARGIN = 40;
const CONTENT_W = PAGE_W - MARGIN * 2;

type Rgb = readonly [number, number, number];

const MUTE: Rgb = [96, 103, 116];
const TEXT: Rgb = [24, 27, 34];
const RULE: Rgb = [190, 196, 206];
const STRIP_BG: Rgb = [242, 244, 247];

export function invoiceNumber(order: AdminOrderDetail): string {
  return `INV-${order.orderNumber || order.orderId}`;
}

export function invoiceFilename(order: AdminOrderDetail): string {
  return `${invoiceNumber(order)}.pdf`;
}

const myr = (n: number) => `RM ${Math.round(n).toLocaleString('en-US')}`;

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function shortDate(d: Date): string {
  return `${String(d.getDate()).padStart(2, '0')} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

export function buildInvoice(order: AdminOrderDetail): jsPDF {
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  let y = MARGIN;

  const ensure = (h: number) => {
    if (y + h > PAGE_H - MARGIN) {
      doc.addPage();
      y = MARGIN;
    }
  };

  const textLeft = (s: string, x: number, size: number, bold = false, color: Rgb = TEXT) => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(size);
    doc.setTextColor(color[0], color[1], color[2]);
    doc.text(s, x, y);
  };

  const textRight = (s: string, x: number, size: number, bold = false, color: Rgb = TEXT) => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(size);
    doc.setTextColor(color[0], color[1], color[2]);
    doc.text(s, x, y, { align: 'right' });
  };

  // ── Header ─────────────────────────────────────────────────────────────────
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(30);
  doc.setTextColor(TEXT[0], TEXT[1], TEXT[2]);
  doc.text('INVOICE', MARGIN, y + 24, { charSpace: 1.5 });

  const right = PAGE_W - MARGIN;
  textRight(invoiceNumber(order), right, 13, true);
  y += 18;
  textRight(`Issued ${shortDate(new Date())}`, right, 10, false, MUTE);
  y += 34;

  // ── Parties ────────────────────────────────────────────────────────────────
  const colX = MARGIN;
  const col2X = MARGIN + CONTENT_W / 2 + 12;
  const startPartyY = y;

  const label = (s: string, x: number) => {
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8.5);
    doc.setTextColor(MUTE[0], MUTE[1], MUTE[2]);
    doc.text(s.toUpperCase(), x, y, { charSpace: 0.8 });
  };

  const partyBlock = (
    x: number,
    heading: string,
    name: string,
    lines: string[]
  ) => {
    y = startPartyY;
    label(heading, x);
    y += 16;
    if (name.trim()) {
      textLeft(name.trim(), x, 12, true);
      y += 15;
    }
    for (const raw of lines) {
      const s = raw.trim();
      if (!s) continue;
      textLeft(s, x, 10, false, TEXT);
      y += 13;
    }
  };

  partyBlock(colX, 'From', 'Intellar Marketplace', ['Online furniture marketplace']);
  partyBlock(col2X, 'To', order.customerName, [
    order.shippingAddress,
    order.customerPhone,
    order.customerEmail,
  ]);
  y = Math.max(y, startPartyY) + 10;

  // ── Reference strip ────────────────────────────────────────────────────────
  const stripParts = [
    order.orderNumber.trim(),
    order.createdAt ? `Order placed ${shortDate(new Date(order.createdAt))}` : '',
    order.paymentMethod.trim() ? `Payment: ${order.paymentMethod.trim()}` : '',
  ].filter(Boolean);

  ensure(30);
  const stripH = 26;
  doc.setFillColor(STRIP_BG[0], STRIP_BG[1], STRIP_BG[2]);
  doc.roundedRect(MARGIN, y - 12, CONTENT_W, stripH, 4, 4, 'F');
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9.5);
  doc.setTextColor(40, 45, 55);
  doc.text(stripParts.join('  ·  '), MARGIN + 12, y + 4);
  y += 34;

  // ── Items table ────────────────────────────────────────────────────────────
  const colQty = MARGIN + 300;
  const colUnit = MARGIN + 380;
  const colAmount = PAGE_W - MARGIN;

  const tableHeader = () => {
    label('Product', MARGIN);
    textRight('Qty', colQty, 8.5, true, MUTE);
    textRight('Unit', colUnit, 8.5, true, MUTE);
    textRight('Amount', colAmount, 8.5, true, MUTE);
    doc.setDrawColor(RULE[0], RULE[1], RULE[2]);
    doc.setLineWidth(0.8);
    doc.line(MARGIN, y + 6, PAGE_W - MARGIN, y + 6);
    y += 20;
  };

  ensure(40);
  tableHeader();

  let units = 0;
  for (const item of order.items) {
    ensure(22);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.setTextColor(TEXT[0], TEXT[1], TEXT[2]);
    doc.text(item.name, MARGIN, y);
    textRight(String(item.quantity), colQty, 10);
    textRight(myr(item.unitPrice), colUnit, 10);
    textRight(myr(item.unitPrice * item.quantity), colAmount, 10);
    units += item.quantity;
    y += 12;
    doc.setDrawColor(225, 228, 234);
    doc.setLineWidth(0.5);
    doc.line(MARGIN, y, PAGE_W - MARGIN, y);
    y += 14;
  }

  if (order.items.length === 0) {
    textLeft('No items on this invoice.', MARGIN, 10, false, MUTE);
    y += 20;
  } else {
    y += 2;
    textRight(
      `${order.items.length} line item${order.items.length === 1 ? '' : 's'} · ${units} unit${units === 1 ? '' : 's'}`,
      PAGE_W - MARGIN,
      9,
      false,
      MUTE
    );
    y += 10;
  }

  // ── Totals ─────────────────────────────────────────────────────────────────
  const totalsBlockW = 270;
  const totalsX = PAGE_W - MARGIN;
  const labelX = totalsX - totalsBlockW;

  const totalLine = (labelText: string, value: string, strong = false) => {
    ensure(18);
    const size = strong ? 13 : 10.5;
    textLeft(labelText, labelX, size, strong);
    textRight(value, totalsX, size, strong);
    y += strong ? 20 : 16;
  };

  y += 6;
  totalLine('Items subtotal', myr(order.subtotal));
  if (order.discount > 0) totalLine('Discount', `-${myr(order.discount)}`);
  totalLine('Shipping', myr(order.shippingFee));
  if (order.tax > 0) totalLine('Tax', myr(order.tax));
  ensure(30);
  doc.setDrawColor(RULE[0], RULE[1], RULE[2]);
  doc.setLineWidth(0.8);
  doc.line(labelX, y - 6, totalsX, y - 6);
  y += 8;
  totalLine('Total', myr(order.total), true);

  // ── Footer ─────────────────────────────────────────────────────────────────
  y += 14;
  ensure(40);
  doc.setDrawColor(RULE[0], RULE[1], RULE[2]);
  doc.setLineWidth(0.6);
  doc.line(MARGIN, y, PAGE_W - MARGIN, y);
  y += 14;
  textLeft(
    `This invoice covers all items on order ${order.orderNumber || order.orderId}.`,
    MARGIN,
    9,
    false,
    MUTE
  );

  const pages = doc.getNumberOfPages();
  for (let i = 1; i <= pages; i++) {
    doc.setPage(i);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(MUTE[0], MUTE[1], MUTE[2]);
    doc.text(
      `${invoiceNumber(order)}  ·  Page ${i} of ${pages}`,
      PAGE_W - MARGIN,
      PAGE_H - 20,
      { align: 'right' }
    );
  }

  return doc;
}

export function downloadInvoice(order: AdminOrderDetail): void {
  buildInvoice(order).save(invoiceFilename(order));
}
