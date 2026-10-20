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
  type ChatState,
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

const stateCartLine = z.object({
  productId: z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/),
  name: z.string().trim().min(1).max(48),
  qty: z.number().int().nonnegative().max(999),
  lineTotal: z.number().finite().nonnegative().max(1e9),
});

const statePlaced = z.object({
  name: z.string().trim().min(1).max(48),
  wCm: z.number().finite().nonnegative().max(100000),
  hCm: z.number().finite().nonnegative().max(100000),
});

const statePlan = z.object({
  name: z.string().trim().max(60).optional(),
  roomType: z.string().trim().max(40).optional(),
  widthCm: z.number().finite().nonnegative().max(100000).optional(),
  heightCm: z.number().finite().nonnegative().max(100000).optional(),
  placed: z.array(statePlaced).max(10).optional(),
  pendingPlacements: z.number().int().nonnegative().max(99).optional(),
});

const stateBudget = z.object({
  capRm: z.number().int().nonnegative().max(100000000),
  room: z.string().trim().max(40).optional(),
  ecoFriendly: z.boolean().optional(),
  estimateRm: z.number().int().nonnegative().max(100000000).optional(),
  remainingRm: z.number().int().max(100000000).optional(),
});

const stateOrder = z.object({
  orderNumber: z.string().trim().min(1).max(64),
  status: z.string().trim().min(1).max(32),
  total: z.number().finite().nonnegative().max(1e9),
  itemCount: z.number().int().nonnegative().max(999),
  placedAt: z.string().trim().max(40).optional(),
});

const chatStateSchema = z.object({
  cart: z
    .object({
      items: z.array(stateCartLine).max(8),
      itemCount: z.number().int().nonnegative().max(9999),
      subtotal: z.number().finite().nonnegative().max(1e9),
    })
    .optional(),
  plan: statePlan.optional(),
  budget: stateBudget.optional(),
  orders: z.array(stateOrder).max(3).optional(),
  wishlistCount: z.number().int().nonnegative().max(99999).optional(),
});

const chatBodySchema = z.object({
  messages: z.array(messageSchema).min(1).max(50),
  style: z.string().trim().max(120).optional(),
  room: z.string().trim().max(120).optional(),
  products: z.array(productSchema).max(20).optional(),
  state: chatStateSchema.optional(),
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
        ...(parsed.state ? { state: parsed.state as ChatState } : {}),
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
