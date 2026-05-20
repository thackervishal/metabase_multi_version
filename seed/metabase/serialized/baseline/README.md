# Baseline Serialization

This folder is reserved for future exported Metabase serialization bundles.

The current scaffold seeds the initial users, API key, and sample database through `config.yml`, then creates starter groups and content through `scripts/seed-metabase.sh`.

If you later export a richer baseline from a configured Metabase instance, store it here and extend the seed step to import it.