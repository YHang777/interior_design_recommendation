import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import {
  AiChatException,
  sanitiseSuggestions,
  type AiChatDeps,
  type ChatMessage,
  type ChatProduct,
  type ChatReply,
} from '../services/ai-chat.service';

/**
 * `/api/ai/chat` — the design assistant used by the mobile app.
 *
 *   POST /api/ai/chat   {messages, style?, room?, products?} → {reply, suggestions}
 *
 * Unlike `/verify-email/send` this is AUTHENTICATED (Firebase ID token) and
 * deliberately so: it is a proxy onto a paid third-party model, and an open
 * one is a bill waiting to happen. The key itself never leaves the server —
 * the app sends a transcript and receives prose plus the catalogue ids to
 * render as add-to-cart cards.
 */

const messageSchema = z.object({
  role: z.enum(['user', 'model']),
  text: z.string().trim().min(1).max(4_000),
});

const productSchema = z.object({
  id: z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/),
  name: z.string().trim().min(1).max(200),
  price: z.number().finite().nonnegative().optional(),
  category: z.string().trim().max(120).optional(),
  designStyle: z.string().trim().max(120).optional(),
  description: z.string().trim().max(400).optional(),
  photoLabels: z.array(z.string().trim().max(60)).max(8).optional(),
  photoSummary: z.string().trim().max(240).optional(),
  photoMismatch: z.boolean().optional(),
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

      let result: ChatReply;
      try {
        result = await deps.generate(request);
      } catch (err) {
        if (err instanceof AiChatException) {
          deps.log?.(`[ai-chat] ${err.kind}: ${err.message}`);
          throw toApiError(err);
        }
        throw err;
      }

      // The model picks ids from the catalogue; anything it invents never
      // reaches the app — the card would be a dead tap.
      const suggestions = sanitiseSuggestions(
        Array.isArray(result.suggestions) ? result.suggestions : [],
        parsed.products
      );
      res.json({ reply: result.reply, suggestions });
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
