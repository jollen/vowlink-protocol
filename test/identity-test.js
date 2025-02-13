/* eslint-env node, mocha */
import * as assert from 'assert';

import { Chain, Channel, Identity, Message } from '../';

describe('Identity', () => {
  it('should be serialized/deserialized with chain', async () => {
    const id = new Identity('id');
    const channel = await Channel.create(id, 'channel');

    const trustee = new Identity('trustee');

    const link = id.issueLink(channel, {
      trusteePubKey: trustee.publicKey,
      trusteeDisplayName: 'trustee',
    });

    assert.strictEqual(trustee.getChannelIds().length, 0);

    const chain = new Chain([ link ]);
    trustee.addChain(channel, chain);

    assert.strictEqual(trustee.getChannelIds().length, 1);
    assert.strictEqual(trustee.getChannelIds()[0].toString('hex'),
      channel.id.toString('hex'));

    const copy = Identity.deserializeData(trustee.serializeData());
    assert.strictEqual(copy.publicKey.toString('hex'),
      trustee.publicKey.toString('hex'));

    await channel.post(Message.json('test'), copy);
  });
});
