const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { AccessToken } = require("livekit-server-sdk");

setGlobalOptions({ maxInstances: 10 });

const LIVEKIT_API_KEY = "APIMDPmwfn6mreA";
const LIVEKIT_API_SECRET = "A7S57LVlGLhETfTSKlRaliIvfhCWcoCGmnactYeOXrzB";

exports.createLiveKitToken = onCall(async (request) => {
  const roomId = request.data.roomId;
  const userId = request.data.userId;
  const userName = request.data.userName;

  const token = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
    identity: userId,
    name: userName,
  });

  token.addGrant({
    roomJoin: true,
    room: roomId,
    canPublish: true,
    canSubscribe: true,
  });

  return {
    token: await token.toJwt(),
  };
});