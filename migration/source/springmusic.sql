BEGIN;

CREATE TABLE public.album (
    id character varying(40) NOT NULL,
    album_id character varying(255),
    artist character varying(255),
    genre character varying(255),
    release_year character varying(255),
    title character varying(255),
    track_count integer NOT NULL,
    CONSTRAINT album_pkey PRIMARY KEY (id)
);

INSERT INTO public.album (id, album_id, artist, genre, release_year, title, track_count)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'rehost-001', 'Source Signals', 'Rock', '2017', 'Baseline', 9),
    ('00000000-0000-0000-0000-000000000002', 'rehost-002', 'Packet Route', 'Electronic', '2018', 'Two Egress Paths', 11),
    ('00000000-0000-0000-0000-000000000003', 'rehost-003', 'State Keepers', 'Jazz', '2019', 'No Drift', 7),
    ('00000000-0000-0000-0000-000000000004', 'rehost-004', 'Schema Echo', 'Classical', '2020', 'Compatible Shapes', 12),
    ('00000000-0000-0000-0000-000000000005', 'rehost-005', 'Checksum', 'Ambient', '2021', 'Evidence Trail', 6),
    ('00000000-0000-0000-0000-000000000006', 'rehost-006', 'Restore Point', 'Soul', '2022', 'Rollback Window', 10),
    ('00000000-0000-0000-0000-000000000007', 'rehost-007', 'Cutover Clock', 'Funk', '2023', 'Final Sync', 8),
    ('00000000-0000-0000-0000-000000000008', 'rehost-008', 'Target Service', 'Pop', '2024', 'Running on STACKIT', 13);

COMMIT;