# Cross-chain Rebase Token
1. A protocol that allows user to deposit into a value and in return,receiver rebase tokens that represent theit underlying balance
2. Rebase token-> function of balanceof is dynamic to show the changing balance with time.
- Balance increases linearly with time 
- mint token to our user every time they perform and action(minting,burning,transfering,bridging)
3. interset set decrese with time, but early participant will get original interset rate,This mean to reward the early participant.

# QuickStart
```
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-local@v0.2.5-beta.0
forge install smartcontractkit/ccip@v2.17.0-ccip1.5.16
```
