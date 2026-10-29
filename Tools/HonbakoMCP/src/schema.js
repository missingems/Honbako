import { z } from 'zod';
import { coachingAnnotate } from './coaching-schema.js';
export { coachingPublish, coachingSession, coachingPause } from './coaching-schema.js';
const identity = maximum => z.string().trim().min(1).max(maximum).refine(value => !/[\u0000-\u001f\u007f?#]/.test(value) && !/:[/][/][^/]*@/.test(value), 'Identity cannot contain credentials, query, fragment or control characters');
export const id = identity(256);
const mangaId = identity(2048);
const title = z.string().trim().min(1).max(512);
const iso = z.iso.datetime({ offset: true });
export const item = z.object({ sourceId: id, mangaId });
export const book = item.extend({ title, author: z.string().max(512).optional(), completed: z.boolean().optional(), lastReadPage: z.number().int().min(1).max(1000000).optional() });
export const source = z.object({ id, name: title, supportsSearch: z.boolean() });
export const reading = item.extend({ title, chapterId: identity(2048), chapterTitle: z.string().max(512),
  chapterNumber: z.union([z.number().finite(), z.string().max(40)]).optional(),
  volumeNumber: z.union([z.number().finite(), z.string().max(40)]).optional(),
  page: z.number().int().min(1).max(1000000), lastVisiblePage: z.number().int().min(1).max(1000000).optional(),
  totalPages: z.number().int().min(1).max(1000000).optional(), updatedAt: iso, active: z.boolean() }).superRefine((value, context) => {
  if (value.lastVisiblePage !== undefined && value.lastVisiblePage < value.page) context.addIssue({ code: 'custom', message: 'Visible range is reversed' });
  if (value.totalPages !== undefined && (value.page > value.totalPages || (value.lastVisiblePage ?? value.page) > value.totalPages)) context.addIssue({ code: 'custom', message: 'Visible page exceeds total pages' });
});
export const snapshot = z.object({ schemaVersion: z.literal(1), generatedAt: iso,
  library: z.array(book).max(2000), sources: z.array(source).max(100), reading: reading.nullable().optional(),
  libraryTruncated: z.boolean().optional(), sourcesTruncated: z.boolean().optional() });
export const pairRequest = z.object({ code: z.string().regex(/^\d{6}$/), name: title });
export const statusRequest = z.object({ status: z.enum(['awaitingApproval', 'completed', 'failed', 'rejected']),
  approvalGranted: z.boolean().optional(), result: z.unknown().optional(), error: z.string().max(1000).optional() });
export const searchResult = z.object({ matches: z.array(book).max(20), errors: z.array(z.string().max(512)).max(100).optional() });
export const addResult = z.object({ added: z.array(item.extend({ title: title.optional() })).max(20),
  alreadyPresent: z.array(item.extend({ title: title.optional() })).max(20) });
const device = { deviceId: z.uuid().optional() };
export const toolSchemas = {
  honbako_get_status: z.object({}),
  honbako_get_reading_context: z.object(device),
  honbako_search_library: z.object({ ...device, query: z.string().max(200).default(''), limit: z.number().int().min(1).max(100).default(20) }),
  honbako_list_sources: z.object(device),
  honbako_search_catalog: z.object({ ...device, query: z.string().trim().min(1).max(300), sourceIds: z.array(id).min(1).max(20).optional(), limit: z.number().int().min(1).max(20).default(20) }),
  honbako_add_to_library: z.object({ ...device, items: z.array(item).min(1).max(20), idempotencyKey: z.string().regex(/^[A-Za-z0-9_-]{1,128}$/) }),
  honbako_get_job: z.object({ ...device, jobId: z.uuid() }),
  honbako_cancel_job: z.object({ ...device, jobId: z.uuid() }),
  honbako_get_coaching_page: z.object(device).strict(),
  honbako_annotate_page: coachingAnnotate
};
