import Testing
@testable import VPNLib

@Suite()
struct RingBufferTests {
    @Test
    func belowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)

        buffer.append(1)
        buffer.append(2)

        #expect(buffer.elements.count == 2)
        #expect(buffer.elements == [1, 2])
    }

    @Test
    func toCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)

        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        #expect(buffer.elements.count == 3)
        #expect(buffer.elements == [1, 2, 3])
    }

    @Test
    func pastCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)

        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4)
        buffer.append(5)

        #expect(buffer.elements.count == 3)
        #expect(buffer.elements == [3, 4, 5])
    }

    @Test
    func singleCapacity() {
        var buffer = RingBuffer<Int>(capacity: 1)

        buffer.append(1)
        #expect(buffer.elements == [1])

        buffer.append(2)
        #expect(buffer.elements == [2])

        buffer.append(3)
        #expect(buffer.elements == [3])
    }

    @Test
    func replaceAll() {
        var buffer = RingBuffer<Int>(capacity: 3)

        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        buffer.append(4)
        buffer.append(5)
        buffer.append(6)

        #expect(buffer.elements.count == 3)
        #expect(buffer.elements == [4, 5, 6])
    }

    @Test
    func replacePartial() {
        var buffer = RingBuffer<Int>(capacity: 3)

        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        buffer.append(4)
        buffer.append(5)

        #expect(buffer.elements == [3, 4, 5])

        buffer.append(6)
        buffer.append(7)

        #expect(buffer.elements == [5, 6, 7])
    }
}
