# AIBrain Frontend

React + Vite dashboard for the local AIBrain backend.

## Run

```bash
npm install
npm run dev
```

Default backend targets are configured in `src/api/client.js` and point at:

```text
http://localhost:4000
ws://localhost:4000/api/v1/ws
```

## Build

```bash
npm run build
```

The current build succeeds but Vite warns that the main JavaScript chunk is larger than 500 kB. Code-splitting is a future polish item.
