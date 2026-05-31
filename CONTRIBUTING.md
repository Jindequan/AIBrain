# Contributing

Thanks for your interest in contributing to AIBrain.

## Getting Started

```sh
git clone https://github.com/YOUR_ORG/AIBrain.git
cd AIBrain
make setup
make test
```

## Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make your changes
4. Run tests: `make test`
5. Commit using conventional commit messages: `feat:`, `fix:`, `refactor:`, `docs:`
6. Push and open a Pull Request

## Code Style

- **Elixir**: `mix format` — the project includes a `.formatter.exs`
- **JavaScript/React**: Prettier with the project's config
- Keep PRs focused on a single change

## Architecture

See `docs/architecture.md` for the system design overview.

## Testing

```sh
make test          # run server tests
make test-web      # run frontend tests
```

AIBrain uses ExUnit for the backend and Vitest for the frontend. Write tests for new features and bug fixes.

## License

By contributing, you agree that your contributions will be licensed under the AGPL 3.0 License.
