import {sqliteTable,text,integer,primaryKey} from 'drizzle-orm/sqlite-core';
export const leagues=sqliteTable('leagues',{
  userID:text('user_id').notNull(), id:text('id').notNull(),
  connection:text('connection').notNull(), secret:text('secret'),
  updatedAt:integer('updated_at').notNull()
},table=>[primaryKey({columns:[table.userID,table.id]})]);
export const limits=sqliteTable('request_limits',{
  userID:text('user_id').primaryKey(), window:integer('window').notNull(), count:integer('count').notNull()
});
