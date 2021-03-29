var ZoraSwap = artifacts.require("ZoraSwap");

module.exports = function (developer, network, accounts) {
  developer.deploy(ZoraSwap);
};
