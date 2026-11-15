import server from "./api/rooms.js";

server.listen(Number(process.env.BREAKPOINT_ROOMS_PORT || 8787), "127.0.0.1", () => {
  console.log("BREAKPOINT rooms listening on 127.0.0.1:" + server.address().port);
});
