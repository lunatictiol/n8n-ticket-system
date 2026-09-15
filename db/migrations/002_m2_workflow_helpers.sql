-- 002_m2_workflow_helpers.sql
-- Milestone M2.4 (breakage #5) — the n8n Postgres node sends parameterised
-- queries over the extended protocol, which cannot execute multiple
-- semicolon-separated commands in one call ("cannot insert multiple commands
-- into a prepared statement"). The three multi-statement nodes (Mark Needs
-- Manual, Record Sent + Audit, Record Rejection) are moved here as functions so
-- each node runs exactly one parameterised statement: SELECT fn($1, ...).
-- Forward-only; never edit after applying.

BEGIN;

-- Retrieval below the similarity floor: no draft, park the ticket. -------------
CREATE OR REPLACE FUNCTION mark_needs_manual(p_ticket_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE tickets SET status = 'NEEDS_MANUAL', updated_at = now()
  WHERE id = p_ticket_id;

  INSERT INTO ticket_events (ticket_id, event_type, event_description, actor)
  VALUES (p_ticket_id, 'ai_skipped',
          'Retrieval below similarity floor; no draft generated.', 'system');
END;
$$ LANGUAGE plpgsql;

-- Approved reply sent: mark reply sent, ticket awaiting customer, log the ------
-- outbound message, the event, and the audit row, all in one call. -----------
CREATE OR REPLACE FUNCTION record_sent_audit(
  p_reply_id    uuid,
  p_final_reply text,
  p_actor       text,
  p_ticket_id   uuid,
  p_was_edited  boolean
) RETURNS void AS $$
BEGIN
  UPDATE replies
     SET final_reply = p_final_reply, status = 'sent',
         approved_by = p_actor, approved_at = now(), sent_at = now()
   WHERE id = p_reply_id;

  UPDATE tickets SET status = 'AWAITING_CUSTOMER', updated_at = now()
   WHERE id = p_ticket_id;

  INSERT INTO ticket_messages (ticket_id, direction, from_email, body_text, received_at)
  VALUES (p_ticket_id, 'outbound', p_actor, p_final_reply, now());

  INSERT INTO ticket_events (ticket_id, event_type, event_description, actor)
  VALUES (p_ticket_id, 'reply_sent', 'Approved reply sent to customer.', p_actor);

  INSERT INTO audit_log (actor, actor_role, action, entity_type, entity_id, after)
  VALUES (p_actor, 'agent', 'approve_and_send', 'reply', p_reply_id,
          jsonb_build_object('edited', p_was_edited));
END;
$$ LANGUAGE plpgsql;

-- Draft rejected: mark reply rejected, ticket manual, log event + audit. ------
CREATE OR REPLACE FUNCTION record_rejection(
  p_reply_id  uuid,
  p_reason    text,
  p_actor     text,
  p_ticket_id uuid
) RETURNS void AS $$
BEGIN
  UPDATE replies
     SET status = 'rejected', rejection_reason = p_reason,
         approved_by = p_actor, approved_at = now()
   WHERE id = p_reply_id;

  UPDATE tickets SET status = 'MANUAL', updated_at = now()
   WHERE id = p_ticket_id;

  INSERT INTO ticket_events (ticket_id, event_type, event_description, actor)
  VALUES (p_ticket_id, 'draft_rejected', COALESCE(p_reason, 'No reason given'), p_actor);

  INSERT INTO audit_log (actor, actor_role, action, entity_type, entity_id, after)
  VALUES (p_actor, 'agent', 'reject_draft', 'reply', p_reply_id,
          jsonb_build_object('reason', p_reason));
END;
$$ LANGUAGE plpgsql;

COMMIT;
