// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    // airline to be active if it has paid funds
    struct Airline {
        bool isActive;
        uint256 funds;
        bool isRegistered;
    }

    mapping(address => Airline) private airlines;
    uint256 private numberOfActiveArilines = 0;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
        Passenger[] passengers;
    }
    mapping(bytes32 => Flight) private flights;

    struct Passenger {
        address passenger;
        uint256 insuranceAmount;
        bool insuranceClaimed;
    }

    mapping(address => uint256) private withdrawls;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/
    event InsuranceBought(address, bytes32);
    event InsurancePaid(address, uint256);
    event InsuranceCredited(bool);

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() {
        contractOwner = msg.sender;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
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

    modifier flightRegistered(
        string memory flight,
        uint256 timestamp,
        address airline
    ) {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        require(flights[key].isRegistered, "Flight is not registered");
        _;
    }

    modifier requireInsurance(address _address) {
        require(withdrawls[_address] != 0, "You aren't eligible for insurance");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address _address) external {
        airlines[_address] = Airline({
            isActive: false,
            funds: 0,
            isRegistered: true
        });
    }

    function getNumberOfActiveAirlines() public view returns (uint256) {
        return numberOfActiveArilines;
    }

    function isAirlineRegisteredAndActive(address _address)
        external
        view
        returns (bool)
    {
        return airlines[_address].isActive;
    }

    function isAirlineRegisteredAndActive2(address _address)
        external
        view
        returns (
            bool,
            uint256,
            bool,
            address
        )
    {
        return (
            airlines[_address].isActive,
            airlines[_address].funds,
            airlines[_address].isRegistered,
            _address
        );
    }

    function isAirlineRegistered(address _address)
        external
        view
        returns (bool)
    {
        return airlines[_address].isRegistered;
    }

    function registerFlight(
        bytes32 key,
        uint8 statusCode,
        uint256 timestamp,
        address airline
    ) external requireIsOperational returns (bool) {
        require(!flights[key].isRegistered, "Flight already registered");
        Flight storage flight = flights[key];
        flight.isRegistered = true;
        flight.statusCode = statusCode;
        flight.updatedTimestamp = timestamp;
        flight.airline = airline;
        return true;
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy(
        string memory flight,
        uint256 timestamp,
        address airline,
        uint256 amount
    )
        external
        payable
        requireIsOperational
        flightRegistered(flight, timestamp, airline)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        flights[key].passengers.push(
            Passenger({
                passenger: msg.sender,
                insuranceAmount: amount,
                insuranceClaimed: false
            })
        );
        emit InsuranceBought(msg.sender, key);
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(bytes32 key) internal requireIsOperational {
        Passenger[] memory passengers = flights[key].passengers;
        for (uint256 i = 0; i < passengers.length; i++) {
            uint256 amount = passengers[i].insuranceAmount;
            uint256 multiplier = uint256(15).div(10);
            withdrawls[passengers[i].passenger] = amount.mul(multiplier);
        }
        emit InsuranceCredited(true);
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(
        string memory flight,
        uint256 timestamp,
        address airline
    ) external payable requireIsOperational requireInsurance(msg.sender) {
        bool wasPassengerInFlight = false;
        bytes32 key = getFlightKey(airline, flight, timestamp);
        Passenger[] memory passengers = flights[key].passengers;
        for (uint256 i = 0; i < passengers.length; i++) {
            if (passengers[i].passenger == msg.sender) {
                passengers[i].insuranceClaimed = true;
                wasPassengerInFlight = true;
                break;
            }
        }
        if (wasPassengerInFlight == true) {
            uint256 amount = withdrawls[msg.sender];
            require(amount > 0, "Insufficient amount to pay");
            delete withdrawls[msg.sender];
            address payable passenger = payable(msg.sender);
            passenger.transfer(amount);
            emit InsurancePaid(msg.sender, amount);
        }
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund(address _address, uint256 funds)
        public
        payable
        requireIsOperational
    {
        airlines[_address].isActive = true;
        airlines[_address].funds = funds;
        numberOfActiveArilines = numberOfActiveArilines.add(1);
    }

    function processFlightStatus(bytes32 key, uint8 statusCode)
        external
        requireIsOperational
        returns (bool)
    {
        if (flights[key].statusCode != statusCode) {
            flights[key].statusCode = statusCode;
            if (statusCode == 20 || statusCode == 40) {
                creditInsurees(key);
            }
            return true;
        }
        return false;
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    fallback() external payable {
        require(msg.data.length == 0);
        fund(msg.sender, msg.value);
    }

    receive() external payable {}
}
