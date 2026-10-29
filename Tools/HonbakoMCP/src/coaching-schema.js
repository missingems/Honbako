import { z } from 'zod';

export const MAX_COACHING_IMAGE = 350 * 1024;
export const COACHING_LIFETIME_MS = 10 * 60 * 1000;
const identity = maximum => z.string().trim().min(1).max(maximum).refine(value => !/[\u0000-\u001f\u007f?#]/.test(value) && !/:[/][/][^/]*@/.test(value), 'Invalid identity');
const iso = z.iso.datetime({ offset: true });
const unit = z.number().finite().min(0).max(1);
const point = z.object({ x: unit, y: unit }).strict();
const rect = z.object({ x: unit, y: unit, width: unit.gt(0), height: unit.gt(0) }).strict().superRefine((value, ctx) => {
  if (value.x + value.width > 1 || value.y + value.height > 1) ctx.addIssue({ code: 'custom', message: 'Rectangle exceeds the page' });
});
const mark = { id: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/), color: z.enum(['yellow', 'blue', 'green', 'pink']).optional() };
export const coachingAnnotation = z.discriminatedUnion('type', [
  z.object({ ...mark, type: z.literal('box'), rect }).strict(),
  z.object({ ...mark, type: z.literal('arrow'), from: point, to: point }).strict().superRefine((value, ctx) => {
    if (value.from.x === value.to.x && value.from.y === value.to.y) ctx.addIssue({ code: 'custom', message: 'Arrow needs two distinct points' });
  }),
  z.object({ ...mark, type: z.literal('label'), rect, text: z.string().trim().min(1).max(280).refine(value => !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value), 'Invalid label') }).strict(),
  z.object({ ...mark, type: z.literal('stroke'), points: z.array(point).min(2).max(128) }).strict()
]);
export const coachingAnnotations = z.array(coachingAnnotation).max(24).superRefine((marks, ctx) => {
  if (new Set(marks.map(mark => mark.id)).size !== marks.length) ctx.addIssue({ code: 'custom', message: 'Annotation IDs must be unique' });
});
export const coachingPage = z.object({
  pageId: z.uuid(), contentHash: z.string().regex(/^[0-9a-f]{64}$/), sourceId: identity(256), mangaId: identity(2048),
  title: z.string().trim().min(1).max(512), chapterId: identity(2048), chapterTitle: z.string().max(512),
  chapterNumber: z.union([z.number().finite(), z.string().max(40)]).optional(),
  page: z.number().int().min(1).max(1000000), totalPages: z.number().int().min(1).max(1000000).optional(),
  lastVisiblePage: z.number().int().min(1).max(1000000).optional(), capturedAt: iso
}).strict().superRefine((value, ctx) => {
  if (value.lastVisiblePage !== undefined && value.lastVisiblePage < value.page) ctx.addIssue({ code: 'custom', message: 'Visible range is reversed' });
  if (value.totalPages !== undefined && Math.max(value.page, value.lastVisiblePage ?? value.page) > value.totalPages) ctx.addIssue({ code: 'custom', message: 'Page exceeds chapter' });
});
export const coachingPublish = z.object({ sessionId: z.uuid(), pageGeneration: z.number().int().min(1).max(1000000),
  page: coachingPage, image: z.object({ mimeType: z.literal('image/jpeg'), data: z.string().min(4).max(4 * Math.ceil(MAX_COACHING_IMAGE / 3)),
    width: z.number().int().min(1).max(4096), height: z.number().int().min(1).max(4096) }).strict(), expiresAt: iso.nullable().optional(), accessMode: z.literal('connection').optional() }).strict().superRefine((value, ctx) => {
  if (value.accessMode === 'connection' ? value.expiresAt != null : typeof value.expiresAt !== 'string')
    ctx.addIssue({ code: 'custom', message: 'Use connection access without an expiry, or an explicit legacy expiry' });
});
export const coachingPause = z.object({ sessionId: z.uuid(), pageGeneration: z.number().int().min(1).max(1000000), pageId: z.uuid().optional() }).strict();
export const coachingSession = z.object({ sessionId: z.uuid() }).strict();
export const coachingAnnotate = z.object({ deviceId: z.uuid().optional(), sessionId: z.uuid(), pageGeneration: z.number().int().min(1).max(1000000),
  pageId: z.uuid(), contentHash: z.string().regex(/^[0-9a-f]{64}$/), baseRevision: z.number().int().min(0).max(1000000), annotations: coachingAnnotations }).strict();
