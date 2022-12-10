library events;

pub struct CancelEvent {
    cancelled_nonce: u64,
    user: b256,
}

pub struct ExecutedEvent {
    data: b256, // TODO: change to Bytes when implemented: https://github.com/FuelLabs/sway/pull/3454
    nonce: u64,
    to: Identity,
    value: u64,
}

pub struct TransferEvent {
    asset: ContractId,
    nonce: u64,
    to: Identity,
    value: u64,
}
