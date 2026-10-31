import { z } from 'zod';
const safeID = z.string().min(1).max(2048).refine(s => !/[\u0000-\u001f\u007f?#]/.test(s) && !/:[/][/][^/]*@/.test(s));
export const repositoryURL = z.url().max(2048).refine(text => {
  const u = new URL(text);
  return u.protocol === 'https:' && !u.username && !u.password && !u.search && !u.hash;
}, 'Use a credential-free HTTPS repository URL without query or fragment');
export const sourceChange = z.discriminatedUnion('action', [
  ...['install', 'enable', 'disable', 'remove'].map(action => z.object({ action: z.literal(action), sourceId: safeID.max(256) }).strict()),
  ...['add_repository', 'remove_repository', 'refresh_repositories'].map(action => action === 'refresh_repositories'
    ? z.object({ action: z.literal(action) }).strict()
    : z.object({ action: z.literal(action), repositoryURL }).strict())
]);
export const historyQuery = {
  offset: z.number().int().min(0).max(2147483646).default(0),
  limit: z.number().int().min(1).max(100).default(50),
  before: z.iso.datetime({ offset: true }).optional()
};
export const historyEntry = z.object({ sourceId: safeID.max(256), mangaId: safeID, chapterId: safeID,
  title: z.string().max(512), chapterTitle: z.string().max(512),
  chapterNumber: z.number().finite().optional(), volumeNumber: z.number().finite().optional(),
  page: z.number().int().min(1).max(1000000).optional(), totalPages: z.number().int().min(1).max(1000000).optional(),
  completed: z.boolean(), readAt: z.iso.datetime({ offset: true }) });
export const historyResult = z.object({ entries: z.array(historyEntry).max(100), nextOffset: z.number().int().min(0).nullable(),
  before: z.iso.datetime({ offset: true }), observedAt: z.iso.datetime({ offset: true }),
  coverage: z.literal('saved_chapter_history'), excludedRecords: z.number().int().min(0) });
export const sourceCatalogResult = z.object({
  sources: z.array(z.object({ sourceId: safeID.max(256), name: z.string().max(512), installed: z.boolean(), disabled: z.boolean(),
    repositoryURL: repositoryURL.optional() })).max(100),
  repositories: z.array(z.object({ url: repositoryURL, name: z.string().max(512), available: z.boolean() })).max(100),
  nextOffset: z.number().int().min(0).nullable(), observedAt: z.iso.datetime({ offset: true })
});
export const sourceChangeResult = z.object({ change: sourceChange, applied: z.literal(true), observedAt: z.iso.datetime({ offset: true }) });
