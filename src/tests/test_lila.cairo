use starknet::ContractAddress;
use snforge_std::trace::{CallTrace, CallEntryPoint, CallType, EntryPointType, get_call_trace};
use snforge_std::{declare, ContractClassTrait};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Dispatcher
};
use lila_on_starknet::ILilaDispatcher;
use lila_on_starknet::ILilaDispatcherTrait;
use core::poseidon::PoseidonTrait;
use core::hash::{HashStateTrait, HashStateExTrait};
use snforge_std::{start_prank, stop_prank, CheatTarget, start_warp};

fn deploy_contract(name: felt252) -> ContractAddress {
    let contract = declare(name);
    contract.deploy(@ArrayTrait::new()).unwrap()
}

fn deploy_erc20() -> (ERC20ABIDispatcher, ContractAddress) {
    // let recipient: felt252 = starknet::get_caller_address().into();
    // let contract = declare('ERC20');
    // let mut calldata = ArrayTrait::new();
    // let contract_address = contract.deploy(@calldata).unwrap();

    let token_address: ContractAddress = 0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8.try_into().unwrap();
    let token = ERC20ABIDispatcher { contract_address: token_address };
    let USDT_SHAREHOLDER: ContractAddress =
        0x00c318445d5a5096e2ad086452d5c97f65a9d28cafe343345e0fa70da0841295.try_into().unwrap();

    let this = starknet::get_contract_address();
    start_prank(
        CheatTarget::One(token_address),
        USDT_SHAREHOLDER
    );
    token.transfer(
        this,
        100 * 1000000
    );
    stop_prank(CheatTarget::One(token_address));

    (token, token_address)
}


#[test]
#[fork("mainnet")]
fn test_create_order() {
    let lila_address = deploy_contract('Lila');
    let lila_dispatcher = ILilaDispatcher { contract_address: lila_address };

    let amount : felt252 = 100 * 1000000;
    let interest: u256 = 3;
    let term_time : u64 = 1;
    let strategy : felt252 = 0;
    let this = starknet::get_contract_address();

    let id = create_order(
        amount,
        interest,
        term_time,
        strategy,
        lila_address
    );

    let order = lila_dispatcher.get_order(id);

    // assertion
    assert!(order.amount == amount);
    assert!(order.user == this);
    assert!(order.interest == interest);
    assert!(order.strategy == strategy);
    assert!(order.term_time == term_time);
}


#[test]
#[fork("mainnet")]
fn test_fulfil_order() {
    let zUSDT_address: ContractAddress =
       0x00811d8da5dc8a2206ea7fd0b28627c2d77280a515126e62baa4d78e22714c4a.try_into().unwrap();
    let zUSDT = ERC20ABIDispatcher { contract_address: zUSDT_address};
    let (erc_dispatcher, _) = deploy_erc20();

    let lila_address = deploy_contract('Lila');
    let lila_dispatcher = ILilaDispatcher { contract_address: lila_address };

    let amount : felt252 = 100 * 1000000;
    let interest: u256 = 3;
    let term_time : u64 = 1;
    let strategy : felt252 = 0;

    let id = create_order(
        amount,
        interest,
        term_time,
        strategy,
        lila_address
    );

    // FullFill Order
    let order = lila_dispatcher.get_order(id);
    let interest_amount = order.amount.into() * order.interest / 100;

    erc_dispatcher.approve(lila_address, interest_amount);
    lila_dispatcher.fulfill_order(id);

    // assert!(zUSDT.balance_of(lila_address) == 100 * 1000000);
    assert!(erc_dispatcher.balance_of(lila_address) == interest_amount);

}

#[test]
#[fork("mainnet")]
fn test_createAndFullFillThenWithdraw_order() {
    let zUSDT_address: ContractAddress =
       0x00811d8da5dc8a2206ea7fd0b28627c2d77280a515126e62baa4d78e22714c4a.try_into().unwrap();
    let zUSDT = ERC20ABIDispatcher { contract_address: zUSDT_address};
    let (erc_dispatcher, _) = deploy_erc20();

    let lila_address = deploy_contract('Lila');
    let lila_dispatcher = ILilaDispatcher { contract_address: lila_address };

    let amount : felt252 = 100 * 1000000;
    let interest: u256 = 3;
    let term_time : u64 = 1;
    let strategy : felt252 = 0;

    let id = create_order(
        amount,
        interest,
        term_time,
        strategy,
        lila_address
    );

    // FullFill Order
    let mut order = lila_dispatcher.get_order(id);
    let interest_amount = order.amount.into() * order.interest / 100;

    erc_dispatcher.approve(lila_address, interest_amount);
    lila_dispatcher.fulfill_order(id);

    // assert!(zUSDT.balance_of(lila_address) == 100 * 1000000);
    assert!(erc_dispatcher.balance_of(lila_address) == interest_amount);
    let mut order = lila_dispatcher.get_order(id);
    let roll_time = starknet::get_block_timestamp() + 315360;
    let zklend: ContractAddress =
        0x04c0a5193d58f74fbace4b74dcf65481e734ed1714121bdc571da345540efa05.try_into().unwrap();

    start_warp(CheatTarget::One(zklend), roll_time);
    start_prank(
        CheatTarget::One(lila_address),
        order.maker
    );
    lila_dispatcher.withdraw(id);
    stop_prank(CheatTarget::One(lila_address));

}


fn create_order(
    amount: felt252,
    interest: u256,
    term_time: u64,
    strategy: felt252,
    lila_address: ContractAddress
) -> felt252 {
    let this = starknet::get_contract_address();
    let (erc_dispatcher, erc_address) = deploy_erc20();
    let lila_dispatcher = ILilaDispatcher { contract_address: lila_address };
    let zklend: ContractAddress =
        0x04c0a5193d58f74fbace4b74dcf65481e734ed1714121bdc571da345540efa05.try_into().unwrap();

    erc_dispatcher.approve(
        lila_address,
        amount.into()
    );
    lila_dispatcher.set_strategy(
        erc_address,
        zklend
    );

    let nonce = lila_dispatcher.get_nonce(starknet::get_contract_address());
    let id = PoseidonTrait::new().update(this.into()).update(nonce.into()).finalize();

    lila_dispatcher.create_order(amount, interest, term_time, strategy);

    id
}
