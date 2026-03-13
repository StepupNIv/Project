-- ─── DevOps Practice DB Init ─────────────────────────────────────────────────
-- Runs automatically when MySQL container starts for the first time

CREATE DATABASE IF NOT EXISTS devopsdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE devopsdb;

-- ─── Users Table ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id         INT UNSIGNED   NOT NULL AUTO_INCREMENT,
  name       VARCHAR(100)   NOT NULL,
  email      VARCHAR(255)   NOT NULL UNIQUE,
  status     ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_email  (email),
  INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── Seed Data ────────────────────────────────────────────────────────────────
INSERT IGNORE INTO users (name, email) VALUES
  ('Alice DevOps',   'alice@devops.local'),
  ('Bob Jenkins',    'bob@devops.local'),
  ('Charlie Docker', 'charlie@devops.local'),
  ('Diana K8s',      'diana@devops.local');

-- ─── App Health Table ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_health_log (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  checked_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status     VARCHAR(20)  NOT NULL,
  details    JSON,
  PRIMARY KEY (id),
  INDEX idx_checked_at (checked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── Grant Permissions ────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON devopsdb.* TO 'appuser'@'%';
FLUSH PRIVILEGES;

SELECT 'Database initialized successfully' AS message;
