import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import {
  AiChatException,
  type AiChatDeps,
  type ChatMessage,
  type ChatProduct,
} from '../services/ai-chat.service';

/**
 * `/api/ai/chat` — the design assistant used by the mobile app.
 *
 *   POST /api/ai/chat   {messages, style?, room?, products?} → {reply}
 *
 * Unlike `/verify-email/send` this is AUTHENTICATED (Firebase ID token) and
 * deliberately so: it is a proxy onto a paid third-party model, and an open
 * one is a bill waiting to happen. The key itself never leaves the server —
 * the app sends a transcript and receives prose.
 */

const messageSchema = z.object({
  role: z.enum(['user', 'model']),
  text: z.string().trim().min(1).max(4_000),
});

const productSchema = z.object({
  name: z.string().trim().min(1).max(200),
  price: z.number().finite().nonnegative().optional(),
  category: z.string().trim().max(120).optional(),
});

const chatBodySchema = z.object({
  messages: z.array(messageSchema).min(1).max(50),
  style: z.string().trim().max(120).optional(),
  room: z.string().trim().max(120).optional(),
  products: z.array(productSchema).max(20).optional(),
});

export function createAiChatRouter(deps: AiChatDeps): Router {
  const router = Router();

  router.post(
    '/chat',
    deps.authorize,
    validateBody(chatBodySchema),
    asyncHandler(async (req: Request, res: Response) => {
      if (!deps.isConfigured()) {
        throw new ApiError(
          503,
          'NOT_CONFIGURED',
          'AI chat is not configured yet.'
        );
      }

      // validateBody rejects bad shapes but hands the raw body on, so parse
      // here to get the typed, stripped values the service expects.
      const parsed = chatBodySchema.parse(req.body ?? {});

      const request = {
        messages: parsed.messages as ChatMessage[],
        style: parsed.style,
        room: parsed.room,
        products: parsed.products as ChatProduct[] | undefined,
      };

      let reply: string;
      try {
        reply = await deps.generate(request);
      } catch (err) {
        if (err instanceof AiChatException) {
          deps.log?.(`[ai-chat] ${err.kind}: ${err.message}`);
          throw toApiError(err);
        }
        throw err;
      }

      res.json({ reply });
    })
  );

  return router;
}

/**
 * Maps a service failure onto an HTTP status with a sentence for the person
 * waiting on a reply. The underlying diagnostic stays in the log — it names
 * model ids and HTTP codes, which mean nothing to a customer.
 */
function toApiError(err: AiChatException): ApiError {
  switch (err.kind) {
    case 'not-configured':
      return new ApiError(503, 'NOT_CONFIGURED', 'AI chat is not configured yet.');
    case 'timeout':
      return new ApiError(
        504,
        'UPSTREAM_TIMEOUT',
        'The design assistant took too long to reply. Try again.'
      );
    case 'invalid':
      return new ApiError(400, 'VALIDATION_ERROR', 'Invalid chat request.');
    case 'upstream':
      return new ApiError(
        502,
        'UPSTREAM_ERROR',
        'The design assistant could not reply. Try again.'
      );
  }
}
