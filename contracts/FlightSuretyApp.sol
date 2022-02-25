// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/
    uint256 private constant MIN_FUND = 10 ether;

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner; // Account used to deploy contract
    bool private operational = true;

    struct Airline {
        address airlineAddress;
        address[] voters;
    }

    bool private isFirstAirline = true;
    FlightSuretyData flightSuretyDataContract;
    address[] private consensus = new address[](0);

    /********************************************************************************************/
    /*                                       Events                                             */
    /********************************************************************************************/

    event AirlineRegistered(address);
    event AirlineIsActive(address);
    event FlightRegistered(bytes32);
    event FlightStatusChanged(bytes32, uint8);

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address contractAddress) {
        contractOwner = msg.sender;
        flightSuretyDataContract = FlightSuretyData(contractAddress);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      This is used on all state changing functions to pause the contract in
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        // Modify to call data contract's status
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireNewAirline(address _address) {
        require(
            flightSuretyDataContract.isAirlineRegisteredAndActive(_address) ==
                false,
            "Airline is already registered"
        );
        _;
    }

    modifier requireMinFund() {
        require(msg.value >= MIN_FUND, "Insufficient fund");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool) {
        return operational; // Modify to call data contract's status
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    function registerAirline(address _address)
        external
        requireNewAirline(_address)
        requireIsOperational
    {
        if (isFirstAirline == true && msg.sender == contractOwner) {
            flightSuretyDataContract.registerAirline(_address);
            isFirstAirline = false;
            emit AirlineRegistered(_address);
            return;
        }

        require(
            flightSuretyDataContract.isAirlineRegisteredAndActive(msg.sender),
            "Unregistered or inactive airlines cannot vote."
        );
        if (flightSuretyDataContract.getNumberOfActiveAirlines() < 4) {
            flightSuretyDataContract.registerAirline(_address);
            emit AirlineRegistered(_address);
            return;
        }

        bool isDuplicate = false;
        for (uint32 i = 0; i < consensus.length; i++) {
            if (consensus[i] == msg.sender) {
                isDuplicate = true;
                break;
            }
        }

        require(!isDuplicate, "You have already voted");

        consensus.push(msg.sender);
        if (
            consensus.length >=
            flightSuretyDataContract.getNumberOfActiveAirlines().div(2)
        ) {
            flightSuretyDataContract.registerAirline(_address);
            consensus = new address[](0);
            emit AirlineRegistered(_address);
        }
    }

    function fund(address _address) external payable requireMinFund {
        require(
            flightSuretyDataContract.isAirlineRegistered(msg.sender),
            "Airline not registered"
        );
        flightSuretyDataContract.fund(_address, msg.value);
        emit AirlineIsActive(msg.sender);
    }

    function registerFlight(
        string memory flight,
        uint256 timestamp,
        address airline
    ) external requireIsOperational {
        require(
            flightSuretyDataContract.isAirlineRegisteredAndActive(msg.sender),
            "Unregistered or inactive airlines cannot register flights."
        );
        bytes32 key = getFlightKey(airline, flight, timestamp);
        bool isRegistered = flightSuretyDataContract.registerFlight(
            key,
            STATUS_CODE_ON_TIME,
            timestamp,
            airline
        );
        require(isRegistered, "Flight registration failed");
        emit FlightRegistered(key);
    }

    function processFlightStatus(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) internal {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        bool status = flightSuretyDataContract.processFlightStatus(
            key,
            statusCode
        );
        if (status == true) {
            emit FlightStatusChanged(key, statusCode);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        ResponseInfo storage responseInfo = oracleResponses[key];
        responseInfo.requester = msg.sender;
        responseInfo.isOpen = true;
        emit OracleRequest(index, airline, flight, timestamp);
    }

    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );

    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() external view returns (uint8[3] memory) {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) external {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (
            oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES
        ) {
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account)
        internal
        returns (uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++), account)
                )
            ) % maxValue
        );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    // endregion
}

abstract contract FlightSuretyData {
    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }

    function registerAirline(address _address) external virtual;

    function isAirlineRegisteredAndActive(address _address)
        external
        view
        virtual
        returns (bool);

    function getNumberOfActiveAirlines() public view virtual returns (uint256);

    function registerFlight(
        bytes32 key,
        uint8 statusCode,
        uint256 timestamp,
        address airline
    ) external virtual returns (bool);

    function processFlightStatus(bytes32 key, uint8 statusCode)
        external
        virtual
        returns (bool);

    function fund(address _address, uint256 funds) public payable virtual;

    function isAirlineRegistered(address _address)
        external
        view
        virtual
        returns (bool);
}
