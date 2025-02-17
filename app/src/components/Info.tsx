import { drizzleConnect } from "drizzle-react";
import React, { Component, Fragment } from "react";
import PropTypes from "prop-types";

import BuyForm from "./BuyModal";
import ContractData from "./ContractData";

class BuyArtworkSection extends Component {
  render() {
    return (
      <Fragment>
        <h2>Buy Artwork</h2>
        {window.ethereum !== undefined ? (
          <Fragment>
            <p>You will pay <ContractData contract="Vitalik" method="price" toEth /> ETH.<br /> Add your own sale price and amount you want to deposit for patronage: </p>
            <BuyForm contract="Vitalik" method="buy" labels={["Your Initial Sale Price"]} valueLabel="Your Initial Deposit" sendArgs={{}} />
          </Fragment>
        ) : (
            <Fragment>
              [In order to buy the artwork and become a patron you need to have a web3/Ethereum-enabled browser. Please download
            the <a href="https://metamask.io">MetaMask Chrome extension</a> or open in an Ethereum mobile browser.]
          </Fragment>
          )}
      </Fragment>
    )
  }
}

/*
 * Export connected component.
 */

const mapStateToProps = (state: any) => {
  return {
    contracts: state.contracts,
    drizzleStatus: state.drizzleStatus,
    web3: state.web3,
  };
};

export default drizzleConnect(BuyArtworkSection, mapStateToProps);
