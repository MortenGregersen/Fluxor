/*
 * FluxorTests
 *  Copyright (c) Morten Bjerg Gregersen 2020
 *  MIT license, see LICENSE file for details
 */

import Combine
@testable import Fluxor
import FluxorTestSupport
import XCTest

// swiftlint:disable force_cast

class StoreTests: XCTestCase {
    private var store: Store<TestState>!
    private var reducer: ((TestState, Action) -> TestState)!

    override func setUp() {
        super.setUp()
        store = Store(initialState: TestState(type: .initial, lastAction: nil))
    }

    /// Does the `Reducer`s get called?
    func testDispatchUsesReducers() {
        // Given
        let action = TestAction()
        XCTAssertEqual(store.state.value.type, .initial)
        XCTAssertNil(store.state.value.lastAction)
        store.register(reducer: testReducer)
        store.register(reducer: Reducer<TestState> { state, action in
            state.type = .modifiedAgain
            state.lastAction = String(describing: action)
        })
        // When
        store.dispatch(action: action)
        // Then
        XCTAssertEqual(store.state.value.type, .modifiedAgain)
        XCTAssertEqual(store.state.value.lastAction, String(describing: action))
    }

    /// Does the `Effects` get triggered?
    func testEffects() {
        // Given
        let interceptor = TestInterceptor<TestState>()
        TestEffects.threadCheck = { XCTAssertEqual(Thread.current, Thread.main) }
        store.register(effects: TestEffects())
        store.register(interceptor: interceptor)
        let firstAction = TestAction()
        // When
        store.dispatch(action: firstAction)
        // Then
        wait(for: [TestEffects.expectation], timeout: 1)
        let dispatchedActions = interceptor.stateChanges.map(\.action)
        XCTAssertEqual(dispatchedActions.count, 4)
        XCTAssertEqual(dispatchedActions[0] as! TestAction, firstAction)
        XCTAssertEqual(dispatchedActions[1] as! AnonymousAction<Void>, TestEffects.responseAction)
        XCTAssertEqual(dispatchedActions[2] as! AnonymousAction<Int>, TestEffects.generateAction)
        XCTAssertEqual(dispatchedActions[3] as! AnonymousAction<Void>, TestEffects.unrelatedAction)
        XCTAssertEqual(TestEffects.lastAction, TestEffects.generateAction)
    }

    /// Does the `Interceptor` receive the right `Action` and modified `State`?
    func testInterceptors() {
        // Given
        let action = TestAction()
        let interceptor = TestInterceptor<TestState>()
        store.register(reducer: testReducer)
        store.register(interceptor: interceptor)
        let oldState = store.state.value
        XCTAssertEqual(interceptor.stateChanges.count, 0)
        // When
        store.dispatch(action: action)
        // Then
        XCTAssertEqual(interceptor.stateChanges.count, 1)
        XCTAssertEqual(interceptor.stateChanges[0].action as! TestAction, action)
        XCTAssertEqual(interceptor.stateChanges[0].oldState, oldState)
        XCTAssertEqual(interceptor.stateChanges[0].newState, store.state.value)
    }

    /// Does a change in `State` publish new value for `Selector`?
    func testSelectMapPublisher() {
        // Given
        let selector = Selector(keyPath: \TestState.type)
        let store = Store(initialState: TestState(type: .initial, lastAction: nil), reducers: [testReducer])
        let expectation = XCTestExpectation(description: debugDescription)
        let cancellable = store.select(selector).sink {
            if $0 == .modified {
                expectation.fulfill()
            }
        }
        // When
        store.dispatch(action: TestAction())
        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertNotNil(cancellable)
    }

    /// Does a change in `State` publish new value for key path?
    func testSelectKeyPathPublisher() {
        // Given
        let store = Store(initialState: TestState(type: .initial, lastAction: nil), reducers: [testReducer])
        let expectation = XCTestExpectation(description: debugDescription)
        let cancellable = store.select(\.type).sink {
            if $0 == .modified {
                expectation.fulfill()
            }
        }
        // When
        store.dispatch(action: TestAction())
        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertNotNil(cancellable)
    }

    /// Can we select the current value for `Selector`?
    func testSelectMap() {
        // Given
        let selector = Selector(keyPath: \TestState.type)
        let store = Store(initialState: TestState(type: .initial, lastAction: nil), reducers: [testReducer])
        let valueBeforeAction = store.selectCurrent(selector)
        XCTAssertEqual(valueBeforeAction, .initial)
        // When
        store.dispatch(action: TestAction())
        // Then
        let valueAfterAction = store.selectCurrent(selector)
        XCTAssertEqual(valueAfterAction, .modified)
    }

    /// Can we select the current value for key path?
    func testSelectKeyPath() {
        // Given
        let store = Store(initialState: TestState(type: .initial, lastAction: nil), reducers: [testReducer])
        let valueBeforeAction = store.selectCurrent(\.type)
        XCTAssertEqual(valueBeforeAction, .initial)
        // When
        store.dispatch(action: TestAction())
        // Then
        let valueAfterAction = store.selectCurrent(\.type)
        XCTAssertEqual(valueAfterAction, .modified)
    }

    /// Can we get all state changes in a `MockStore`?
    func testMockStoreStateChanges() {
        // Given
        let mockStore = MockStore(initialState: TestState(type: .initial, lastAction: nil))
        let action = TestAction()
        let modifiedState = TestState(type: .modified, lastAction: "Set State")
        // When
        mockStore.dispatch(action: action)
        mockStore.setState(newState: modifiedState)
        // Then
        XCTAssertEqual(mockStore.stateChanges.count, 2)
        XCTAssertEqual(mockStore.stateChanges[0].action as! TestAction, action)
        let setStateAction = mockStore.stateChanges[1].action as! AnonymousAction<TestState>
        XCTAssertEqual(setStateAction.id, "Set State")
        XCTAssertEqual(mockStore.stateChanges[1].newState, modifiedState)
    }

    private struct TestAction: Action, Equatable {}

    private struct TestState: Encodable, Equatable {
        var type: TestType
        var lastAction: String?
    }

    private enum TestType: String, Encodable {
        case initial
        case modified
        case modifiedAgain
    }

    private let testReducer = Reducer<TestState> { state, action in
        state.type = .modified
        state.lastAction = String(describing: action)
    }

    private struct TestEffects: Effects {
        static let responseActionIdentifier = "TestResponseAction"
        static let responseActionTemplate = ActionTemplate(id: TestEffects.responseActionIdentifier)
        static let responseAction = TestEffects.responseActionTemplate.createAction()
        static let generateActionTemplate = ActionTemplate(id: "TestGenerateAction", payloadType: Int.self)
        static let generateAction = TestEffects.generateActionTemplate.createAction(payload: 42)
        static let unrelatedActionTemplate = ActionTemplate(id: "UnrelatedAction")
        static let unrelatedAction = TestEffects.unrelatedActionTemplate.createAction()
        static let expectation = XCTestExpectation()
        static var lastAction: AnonymousAction<Int>?
        static var threadCheck: (() -> Void)!

        let testEffect = Effect.dispatchingOne {
            $0.ofType(TestAction.self)
                .receive(on: DispatchQueue.global(qos: .background))
                .map { _ in TestEffects.responseAction }
                .eraseToAnyPublisher()
        }

        let anotherTestEffect = Effect.dispatchingMultiple {
            $0.withIdentifier(TestEffects.responseActionIdentifier)
                .handleEvents(receiveOutput: { _ in TestEffects.threadCheck() })
                .map { _ in [TestEffects.generateAction, TestEffects.unrelatedAction] }
                .eraseToAnyPublisher()
        }

        let yetAnotherTestEffect = Effect.nonDispatching {
            $0.wasCreated(from: TestEffects.generateActionTemplate)
                .sink(receiveValue: { action in
                    TestEffects.lastAction = action
                    TestEffects.expectation.fulfill()
                })
        }
    }
}

extension AnonymousAction: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
