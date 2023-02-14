
**Cedro: A chain Agnostic Liquidity platform**

Cedro is a cross chain liquidity platform where users can lend and borrow across multiple chains within a few clicks. Cedro’s architecture consists of three main components. 

- Branch
- Messenger 
- Root



A branch is deployed across multiple chains, all of which interact with the Root, which is deployed on a single chain that stores the global states of the protocol and passes information across chains. Branches and Root interact using Messenger. This modular design is important for the scalability of the protocol. To add a new chain to the protocol, all we have to do is to deploy the Branch on that chain and establish a connection to the Root.
## **Branch**
The Branch is the main point of interaction for the users for Deposit and Repay operations. For example, if a user wants to deposit USDC in Ethereum, then the user will interact with the depositRequest() function of the Branch in Ethereum. The deposited amount is stored in the USDC Liquidity Pool at Ethereum, the information is sent to the Root using Messenger, and the user receives ceToken on the Root chain.

A Branch handles asset pools on each chain it is deployed to. That means when a user deposits AVAX on Avalanche, it is sent to the AVAX pool which is managed by the Branch itself. There is a pool for each asset listed in Cedro, which stores the fund in the Branch but is managed by Root. To add a new chain to the protocol, the Branch is deployed on that chain and then a Messenger connection is established between the Root and the Branch.
## **Messenger**
Messenger is a stack of multiple generic cross-chain messaging protocols. Messenger analyses different factors like estimated transaction cost, speed, security, etc. to choose a messaging protocol from the stack for a given transaction. The advantage of having a cross-chain messaging protocol aggregator is that it provides another degree of freedom to the user. Users can choose the protocol they want or let Cedro choose it based on their priorities for cost, speed, security, etc. Once a protocol is chosen, it is used to send the desired cross-chain message to/from the Root.
## **Root**
The Root is deployed in a single chain and is the point of connection for all of the Branches. Every Brach is connected to the Root in a bidirectional manner using Messenger.

Root stores all the protocol's global variables, including the total deposited amount across multiple chains, total borrowed amount, Total protocol liquidity, etc. So whenever a user deposits an asset on Chain A, the information is passed to the Root chain, to update the user's liquidity and asset liquidity. Storing such information in the Root helps the protocol be simpler, more organized, and less prone to attacks.

Users interact with the Root for Borrow, Withdraw, and Liquidate operations. This division of operations in Root and Branch is done to optimize the number of cross-chain calls for each operation.

