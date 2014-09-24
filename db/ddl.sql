-- replicated table for cluster centers, will be populated periodically by OLAP
-- systems
CREATE TABLE clusters
(
  id       integer        NOT NULL,
  src      integer        NOT NULL,
  dest     integer        NOT NULL,
  referral integer        NOT NULL,
  agent    integer        NOT NULL,
  CONSTRAINT clusters_pkey PRIMARY KEY (id)
);

-- replicated table for destinations
CREATE TABLE dests
(
  id       integer      NOT NULL,
  url      varchar(127) UNIQUE, -- referral can be null
  CONSTRAINT dests_pkey PRIMARY KEY (id)
);

-- replicated table for user agents
CREATE TABLE agents
(
  id       integer             NOT NULL,
  name     varchar(142) UNIQUE NOT NULL,
  CONSTRAINT agents_pkey PRIMARY KEY (id)
);

-- events
CREATE TABLE events
(
  src      integer        NOT NULL,
  dest     integer        NOT NULL,
  method   varchar(3)     NOT NULL,
  ts       timestamp      NOT NULL,
  size     bigint         NOT NULL,
  referral integer        NOT NULL,
  agent    integer        NOT NULL,
  cluster  integer
);
PARTITION TABLE events ON COLUMN src;

CREATE INDEX event_src_index ON events (src, ts);
CREATE INDEX event_ts_index ON events (ts);

CREATE TABLE attackers
(
  src integer NOT NULL,
  CONSTRAINT attacker_pkey PRIMARY KEY (src)
);

-- export events
CREATE TABLE events_export
(
  src      integer        NOT NULL,
  dest     integer        NOT NULL,
  method   varchar(3)     NOT NULL,
  ts       timestamp      NOT NULL,
  size     bigint         NOT NULL,
  referral integer        NOT NULL,
  agent    integer        NOT NULL
);
EXPORT TABLE events_export;

-- Agg views
CREATE VIEW events_by_second
(
  second_ts,
  src,
  count_values
)
AS SELECT TRUNCATE(SECOND, ts), src, COUNT(*)
   FROM events
   GROUP BY TRUNCATE(SECOND, ts), src;

CREATE VIEW dests_by_second
(
  second_ts,
  dest,
  count_values
)
AS SELECT TRUNCATE(SECOND, ts), dest, COUNT(*)
   FROM events
   GROUP BY TRUNCATE(SECOND, ts), dest;

CREATE VIEW events_by_cluster
(
  second_ts,
  cluster,
  count_values
)
AS SELECT TRUNCATE(SECOND, ts), cluster, COUNT(*)
   FROM events
   WHERE cluster IS NOT NULL
   GROUP BY TRUNCATE(SECOND, ts), cluster;

CREATE TABLE alerts
(
  src  integer   NOT NULL,
  ts   timestamp NOT NULL,
  CONSTRAINT alerts_pkey PRIMARY KEY (src, ts)
);
PARTITION TABLE alerts ON COLUMN src;

CREATE VIEW alerts_by_second
(
  ts,
  counts
)
AS SELECT TRUNCATE(SECOND, ts), COUNT(*)
   FROM alerts
   GROUP BY TRUNCATE(SECOND, ts);

-- stored procedures
CREATE PROCEDURE FROM CLASS events.DeleteAfterDate;
PARTITION PROCEDURE DeleteAfterDate ON TABLE events COLUMN src;

CREATE PROCEDURE FROM CLASS events.DeleteOldestToTarget;
PARTITION PROCEDURE DeleteOldestToTarget ON TABLE events COLUMN src;

CREATE PROCEDURE FROM CLASS events.NewEvent;
PARTITION PROCEDURE NewEvent ON TABLE events COLUMN src;

CREATE PROCEDURE FROM CLASS events.GetTopUsers;
IMPORT CLASS events.Utils;

CREATE PROCEDURE GetTopDests AS
SELECT dests.url AS url, SUM(count_values) AS counts
FROM dests_by_second, dests
WHERE TO_TIMESTAMP(SECOND, SINCE_EPOCH(SECOND, second_ts) + ?) >= TRUNCATE(SECOND, NOW) AND dest = dests.id
GROUP BY url
ORDER BY counts DESC, url LIMIT ?;

CREATE PROCEDURE GetAlertsPerSec AS
SELECT ts, counts
FROM alerts_by_second
WHERE ts >= TO_TIMESTAMP(SECOND, SINCE_EPOCH(SECOND, NOW) - ?)
ORDER BY ts;

CREATE PROCEDURE GetEventsByCluster AS
SELECT cluster, SUM(count_values) AS counts
FROM events_by_cluster
WHERE TO_TIMESTAMP(SECOND, SINCE_EPOCH(SECOND, second_ts) + ?) >= TRUNCATE(SECOND, NOW)
GROUP BY cluster
ORDER BY cluster;