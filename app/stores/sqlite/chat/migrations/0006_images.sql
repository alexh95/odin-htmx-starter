-- A message's image, by its blob's address in uploads (M6 slice 8); '' for none.
ALTER TABLE chat_messages ADD COLUMN blob TEXT NOT NULL DEFAULT '';
