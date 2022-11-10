contract;

// TODO:
//      - change the "data" in the Tx hashing from b256 to Bytes type when available.
dep interface;
dep data_structures;
dep errors;
dep events;
dep utils;

use std::{
    constants::ZERO_B256,
    context::this_balance,
    identity::Identity,
    logging::log,
    revert::require,
    token::{
        force_transfer_to_contract,
        transfer_to_address,
    },
};

use interface::MultiSignatureWallet;
use data_structures::{SignatureData, User};
use errors::{ExecutionError, InitError};
use events::{ExecutedEvent, TransferEvent};
use utils::{create_hash, recover_signer};

storage {
    /// Used to add entropy into hashing of Tx to decrease the probability of collisions / double
    /// spending.
    nonce: u64 = 0,
    /// The number of approvals required in order to execture a Tx.
    threshold: u64 = 0,
    /// Number of approvals per user.
    weighting: StorageMap<b256, u64> = StorageMap {},
}

impl MultiSignatureWallet for Contract {
    #[storage(read, write)]
    fn constructor(users: Vec<User>, threshold: u64) {
        require(storage.nonce == 0, InitError::CannotReinitialize);
        require(threshold != 0, InitError::ThresholdCannotBeZero);

        let mut user_index = 0;
        while user_index < users.len() {
            require(ZERO_B256 != users.get(user_index).unwrap().address, InitError::AddressCannotBeZero);
            require(users.get(user_index).unwrap().weight != 0, InitError::WeightingCannotBeZero);

            storage.weighting.insert(users.get(user_index).unwrap().address, users.get(user_index).unwrap().weight);
            user_index += 1;
        }

        storage.nonce = 1;
        storage.threshold = threshold;
    }

    #[storage(read, write)]
    fn execute_transaction(
        to: Identity,
        value: u64,
        data: b256,
        signatures_data: Vec<SignatureData>,
    ) {
        require(storage.nonce != 0, InitError::NotInitialized);

        let transaction_hash = create_hash(to, value, data, storage.nonce);
        let approval_count = count_approvals(transaction_hash, signatures_data);

        require(storage.threshold <= approval_count, ExecutionError::InsufficientApprovals);

        storage.nonce += 1;

        // TODO: Execute https://github.com/FuelLabs/sway-applications/issues/22
        log(ExecutedEvent {
            to,
            value,
            data,
            nonce: storage.nonce - 1,
        });
    }

    #[storage(read, write)]
    fn transfer(
        to: Identity,
        asset_id: ContractId,
        value: u64,
        data: b256,
        signatures_data: Vec<SignatureData>,
    ) {
        require(storage.nonce != 0, InitError::NotInitialized);
        require(value <= this_balance(asset_id), ExecutionError::InsufficientAssetAmount);

        let transaction_hash = create_hash(to, value, data, storage.nonce);
        let approval_count = count_approvals(transaction_hash, signatures_data);

        require(storage.threshold <= approval_count, ExecutionError::InsufficientApprovals);

        storage.nonce += 1;

        match to {
            Identity::Address(address) => transfer_to_address(value, asset_id, address),
            Identity::ContractId(address) => force_transfer_to_contract(value, asset_id, address),
        };

        log(TransferEvent {
            to,
            asset: asset_id,
            value,
            nonce: storage.nonce - 1,
        });
    }

    #[storage(read)]
    fn nonce() -> u64 {
        storage.nonce
    }

    fn balance(asset_id: ContractId) -> u64 {
        this_balance(asset_id)
    }

    fn transaction_hash(to: Identity, value: u64, data: b256, nonce: u64) -> b256 {
        create_hash(to, value, data, nonce)
    }
}

/// Takes in a tx hash and signatures with associated data.
/// Recovers a b256 address from each signature;
/// it then increments the number of approvals by that address' approval weighting.
/// Returns the final approval count.
#[storage(read)]
fn count_approvals(transaction_hash: b256, signatures_data: Vec<SignatureData>) -> u64 {
    // The signers must have increasing values in order to check for duplicates or a zero-value.
    let mut previous_signer = b256::min();

    let mut approval_count = 0;
    let mut index = 0;
    while index < signatures_data.len() {
        let signer = recover_signer(transaction_hash, signatures_data.get(index).unwrap());

        require(previous_signer < signer, ExecutionError::IncorrectSignerOrdering);

        previous_signer = signer;
        approval_count += storage.weighting.get(signer);

        if storage.threshold <= approval_count {
            break;
        }

        index += 1;
    }

    approval_count
}
