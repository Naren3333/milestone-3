SHELL := /bin/sh

.PHONY: validate compose-up compose-down k8s-dry-run

validate:
	python scripts/validate.py

compose-up:
	docker compose --env-file .env up -d

compose-down:
	docker compose --env-file .env down

k8s-dry-run:
	kubectl kustomize k8s > /dev/null
