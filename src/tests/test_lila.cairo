use starknet::ContractAddress;
use snforge_std::trace::{CallTrace, CallEntryPoint, CallType, EntryPointType, get_call_trace};
use snforge_std::{start_prank, CheatTarget};

use snforge_std::{declare, ContractClassTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use lila_on_starknet::ILilaDispatcher;
use lila_on_starknet::ILilaDispatcherTrait;

fn deploy_contract(name: felt252) -> ContractAddress {
    let contract = declare(name);
    contract.deploy(@ArrayTrait::new()).unwrap()
}

fn deploy_erc20() -> (IERC20Dispatcher, ContractAddress) {
    let recipient = starknet::contract_address_const::<0x01>();
    let supply: u256 = 20000000;
    let contract = declare('ERC20');
    let mut calldata = array!['MyToken', 'MTK'];
    supply.serialize(ref calldata);
    calldata.append(recipient.into());
    let contract_address = contract.deploy(@calldata).unwrap();
    (IERC20Dispatcher { contract_address }, contract_address)
}

#[test]
fn test_initial_balance() {
    let contract_address = deploy_contract('Lila');

    let dispatcher = ILilaDispatcher { contract_address };

    let balance_before = dispatcher.get_balance();
    assert(balance_before == 0, 'Invalid balance');
}

#[test]
#[available_gas(3000000000000000)]
fn test_balance_of_erc20() {
    let (dispatcher, _) = deploy_erc20();
    let pool = starknet::contract_address_const::<0x01>();
    let balance = dispatcher.balance_of(pool);
    assert(balance == 20000000, 'Invalid Balance');
}

#[test]
fn test_create_order() {
    
    let contract_address = deploy_contract('Lila');
   // println!("{}", get_call_trace());

    let dispatcher = ILilaDispatcher { contract_address };
    let (erc_dispatcher, erc20_address) = deploy_erc20();
    let recipient = starknet::contract_address_const::<0x02>();
    let pool = starknet::contract_address_const::<0x01>();
    let erc20_address_r:felt252 = erc20_address.into();
    println!("{}", erc20_address_r);

    let balance_before = dispatcher.get_balance();
    assert(balance_before == 0, 'Invalid balance');

    let amount : felt252 = 10000;
    let interest: u256 = 3;
    let term_time : u64 = 1;
    let strategy : felt252 = 0;

    dispatcher.set_strategy(erc20_address, recipient);
    let strategy_info = dispatcher.get_strategy(strategy);
    let token_addr: felt252 = strategy_info.token.into();
    println!("{}", token_addr);
    assert(erc20_address_r == token_addr, 'Strategy getter is incorrect');

     start_prank(CheatTarget::One(erc20_address), pool);

    erc_dispatcher.transfer(recipient, 2*amount.into());
    start_prank(CheatTarget::One(erc20_address), recipient);
    //assert(erc_dispatcher.balance_of(recipient) == 2*amount.into(), 'Invalid recipient Balance');

    erc_dispatcher.approve(contract_address, amount.into());

    start_prank(CheatTarget::One(contract_address), recipient);
    let allowance = erc_dispatcher.allowance(recipient,contract_address );
    assert_eq!(allowance, amount.into());

   dispatcher.create_order(amount, interest, term_time, strategy);
    
}


// #[test]
// fn test_fulfil_order() {
//     let contract_address = deploy_contract('Lila');

//     let dispatcher = ILilaDispatcher { contract_address };
//     let (erc_dispatcher, _) = deploy_erc20();

//     let balance_before = dispatcher.get_balance();
//     assert(balance_before == 0, 'Invalid balance');

//     let amount : felt252 = 10000;
//     let interest: u256 = 3;
//     let term_time : u64 = 1;
//     let strategy : u8 = 3;

//     // let mut calldata = array![amount];
//     // interest.serialize(ref calldata);
//     // calldata.append(term_time);
//     // calldata.append(strategy);

//     dispatcher.create_order(amount, interest, term_time, strategy);
    
// }
