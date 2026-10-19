CREATE TABLE `leagues` (
	`user_id` text NOT NULL,
	`id` text NOT NULL,
	`connection` text NOT NULL,
	`secret` text,
	`updated_at` integer NOT NULL,
	PRIMARY KEY(`user_id`, `id`)
);
--> statement-breakpoint
CREATE TABLE `request_limits` (
	`user_id` text PRIMARY KEY NOT NULL,
	`window` integer NOT NULL,
	`count` integer NOT NULL
);
