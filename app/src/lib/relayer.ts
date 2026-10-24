// ponytail: OrangeKit hardcodes the relayer and its gas, drop this once it takes options

// Mezo's testnet relayer moved hosts, the old one answers 403 to every Bitcoin wallet send
const DEAD_RELAYER = "https://test.mezo.org/api/v2/relay/";
const RELAYER = "https://testnet.mezo.org/api/v2/relay/";
const RPC = "https://rpc.test.mezo.org";

type RpcCall = { id: number; method: string };
type RpcReply = { id: number; result?: string };

const send = window.fetch.bind(window);

window.fetch = async (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

    if (url.startsWith(DEAD_RELAYER)) {
        const response = await send(RELAYER + url.slice(DEAD_RELAYER.length), init);
        // A failed relay comes back without a hash and OrangeKit would carry on with 0x
        const body = await response
            .clone()
            .json()
            .catch(() => ({}));
        if (!response.ok || !body.transactionHash) {
            throw new Error(`Relayer rejected the transaction: ${body.error ?? body.message ?? response.status}`);
        }
        return response;
    }

    // Mezo underestimates gas, and a Safe still charges its refund when the call inside runs out
    if (url.startsWith(RPC) && typeof init?.body === "string" && init.body.includes('"eth_estimateGas"')) {
        const calls: RpcCall[] = [JSON.parse(init.body)].flat();
        const estimates = new Set(calls.filter((c) => c.method === "eth_estimateGas").map((c) => c.id));
        const response = await send(input, init);
        const body: RpcReply | RpcReply[] = await response.json();
        const pad = (r: RpcReply) =>
            estimates.has(r.id) && r.result ? { ...r, result: `0x${((BigInt(r.result) * 3n) / 2n).toString(16)}` } : r;
        return new Response(JSON.stringify(Array.isArray(body) ? body.map(pad) : pad(body)), {
            status: response.status,
            headers: response.headers,
        });
    }

    return send(input, init);
};
