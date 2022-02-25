var Test = require("../config/testConfig.js");
var BigNumber = require("bignumber.js");
const { web } = require("webpack");

contract("Flight Surety Tests", async (accounts) => {
  var config;
  before("setup contract", async () => {
    config = await Test.Config(accounts);
    // await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {
    // Get operating status
    let status = await config.flightSuretyData.isOperational();
    assert.equal(status, true, "Incorrect initial operating status value");
  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {
    // Ensure that access is denied for non-Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[0] });
    } catch (e) {
      accessDenied = true;
    }
    assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {
    // Ensure that access is allowed for Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false);
    } catch (e) {
      accessDenied = true;
    }
    assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {
    await config.flightSuretyData.setOperatingStatus(false);

    let reverted = false;
    try {
      await config.flightSurety.setTestingMode(true);
    } catch (e) {
      reverted = true;
    }
    assert.equal(reverted, true, "Access not blocked for requireIsOperational");
    assert.equal(reverted, true, "Access not blocked for requireIsOperational");
    assert.equal(reverted, true, "Access not blocked for requireIsOperational");

    // Set it back for other tests to work
    await config.flightSuretyData.setOperatingStatus(true);
  });

  it("(airline) cannot register an Airline using registerAirline() if it is not funded", async () => {
    // ARRANGE
    let newAirline = accounts[2];
    // ACT
    try {
      await config.flightSuretyApp.registerAirline(newAirline, { from: config.firstAirline });
    } catch (e) {}
    let result = await config.flightSuretyData.isAirlineRegisteredAndActive(newAirline);
    // ASSERT
    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");
  });

  // register first airline by contract owner
  it("(airline) can register first airline only by contract owner", async () => {
    try {
      await config.flightSuretyApp.registerAirline(config.firstAirline, { from: config.owner });
    } catch (e) {}
    let result = await config.flightSuretyData.isAirlineRegistered(config.firstAirline, {
      from: config.owner,
    });
    assert.equal(result, true, "Owner should be able to register first airline");
  });
  // fund first airline
  it("(airline) can fund the first airline", async () => {
    try {
      await config.flightSuretyApp.fund(config.firstAirline, {
        from: config.firstAirline,
        value: web3.utils.toWei("10", "ether"),
      });
    } catch (e) {
      console.log("err", e);
    }

    let result = await config.flightSuretyData.isAirlineRegisteredAndActive(config.firstAirline);
    assert.equal(result, true, "Airline can fund once registered.");
  });
  // register 3 airlines more and check registration logic
  it("(airline) should register 3 airlines and fund", async () => {
    let secondAirline = accounts[3];
    let thirdAirline = accounts[4];
    let fourthAirline = accounts[5];

    let secondAirlineRegistered = false;
    let secondAirlineFunded = false;

    let thirdAirlineRegistered = false;
    let thirdAirlineFunded = false;

    let fourthAirlineRegistered = false;
    let fourthAirlineFunded = false;

    try {
      await config.flightSuretyApp.registerAirline(secondAirline, { from: config.firstAirline });
      secondAirlineRegistered = await config.flightSuretyData.isAirlineRegistered(secondAirline);
      await config.flightSuretyApp.fund(secondAirline, {
        from: secondAirline,
        value: web3.utils.toWei("10", "ether"),
      });
      secondAirlineFunded = await config.flightSuretyData.isAirlineRegisteredAndActive(secondAirline);

      await config.flightSuretyApp.registerAirline(thirdAirline, { from: secondAirline });
      thirdAirlineRegistered = await config.flightSuretyData.isAirlineRegistered(thirdAirline);
      await config.flightSuretyApp.fund(thirdAirline, {
        from: thirdAirline,
        value: web3.utils.toWei("10", "ether"),
      });
      thirdAirlineFunded = await config.flightSuretyData.isAirlineRegisteredAndActive(thirdAirline);

      await config.flightSuretyApp.registerAirline(fourthAirline, { from: thirdAirline });
      fourthAirlineRegistered = await config.flightSuretyData.isAirlineRegistered(fourthAirline);
      await config.flightSuretyApp.fund(fourthAirline, {
        from: fourthAirline,
        value: web3.utils.toWei("10", "ether"),
      });
      fourthAirlineFunded = await config.flightSuretyData.isAirlineRegisteredAndActive(fourthAirline);
    } catch (e) {
      console.log(e);
    }
    assert.equal(secondAirlineRegistered, true, "2nd Airline should be registered");
    assert.equal(thirdAirlineRegistered, true, "3rd Airline should be registered");
    assert.equal(fourthAirlineRegistered, true, "4th Airline should be registered");

    assert.equal(secondAirlineFunded, true, "2nd Airline should be funded");
    assert.equal(thirdAirlineFunded, true, "3rd Airline should be funded");
    assert.equal(fourthAirlineFunded, true, "4th Airline should be funded");
  });
  // 5th airline should await for votes
  it("(airline) should only register airline after 50% of the airlines voted in favor", async () => {
    let secondAirline = accounts[3];
    let thirdAirline = accounts[4];
    let fifthAirline = accounts[6];

    let isAirlineRegistered = false;
    let fifthAirlineRegistered = false;
    let fifthAirlineFunded = false;
    try {
      await config.flightSuretyApp.registerAirline(fifthAirline, { from: secondAirline });
      isAirlineRegistered = await config.flightSuretyData.isAirlineRegistered(fifthAirline);
      await config.flightSuretyApp.registerAirline(fifthAirline, { from: config.firstAirline });
      await config.flightSuretyApp.registerAirline(fifthAirline, { from: thirdAirline });
      fifthAirlineRegistered = await config.flightSuretyData.isAirlineRegistered(fifthAirline);
      await config.flightSuretyApp.fund(fifthAirline, {
        from: fifthAirline,
        value: web3.utils.toWei("10", "ether"),
      });
      fifthAirlineFunded = await config.flightSuretyData.isAirlineRegisteredAndActive(fifthAirline);
    } catch (e) {
      console.log(e);
    }
    assert.equal(isAirlineRegistered, false, "5th Airline should not be registered");
    assert.equal(fifthAirlineRegistered, true, "5th Airline should be registered");
    assert.equal(fifthAirlineFunded, true, "5th Airline should be funded");
  });
});
