# Enemies are simulated lightly on the server and drawn by the client

Up to about 150 living enemies per run (the number is configuration) are plain data on the server: position, health and state, moved by the server without Humanoids or physics. Clients receive the state and draw, animate and interpolate the models. We chose this because Humanoids and physics for that many enemies do not fit a server or a phone, and the server must still decide every hit (rule 1).

## Considered options

- **Humanoid enemies**: the obvious Roblox path, too expensive at horde size.
- **Fewer enemies (about 50)**: would allow Humanoids, but no longer feels like a horde.
