# LilaStark
Fund katana - <br>
```starkli invoke 0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 transfer 0x0044e4d9edffaf455d2a912596cc02f5c04775925626c618a52f90132b2b471c u256:10000000000000000 --account katana0 --rpc http://0.0.0.0:5050```

Deploy contract -<br>
```starkli declare target/dev/lila_on_starknet_Lila.contract_class.json --rpc http://0.0.0.0:5050 --account ~/.starkli-wallets/deployer/account0_account.json --keystore ~/.starkli-wallets/deployer/account0_keystore.json```
