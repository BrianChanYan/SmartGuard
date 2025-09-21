//
//  iPhoneSliderView.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI

struct iPhoneSliderView: View {
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @AppStorage("safeModeActivated") private var isCompleted = false

    var onComplete: () -> Void
    var onStateChanged: ((Bool) -> Void)?

    private func sliderWidth(for screenWidth: CGFloat) -> CGFloat {
        screenWidth - 40
    }

    private let knobSize: CGFloat = 60
    private let cornerRadius: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let currentSliderWidth = sliderWidth(for: geometry.size.width)
            let maxDragDistance = currentSliderWidth - knobSize - 8
            let progress = maxDragDistance > 0 ? dragOffset / maxDragDistance : 0

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: currentSliderWidth, height: knobSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        isCompleted ?
                        AnyShapeStyle(LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 255/255, green: 129/255, blue: 79/255),
                                Color(red: 255/255, green: 180/255, blue: 129/255)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ).opacity(0.8)) :
                        AnyShapeStyle(Color(red: 255/255, green: 129/255, blue: 79/255).opacity(0.6))
                    )
                    .frame(width: dragOffset + knobSize, height: knobSize)
                    .animation(.easeOut(duration: 0.2), value: dragOffset)

                // Slider text
                HStack {
                    if isCompleted {
                        Text("Slide to deactivate")
                            .foregroundColor(.white)
                            .font(.system(size: min(16, currentSliderWidth / 20), weight: .medium))
                            .opacity(0.8)
                            .padding(.leading, 20)
                        Spacer()
                    } else {
                        Spacer()
                        Text("Slide to activate guard mode")
                            .foregroundColor(.white)
                            .font(.system(size: min(16, currentSliderWidth / 20), weight: .medium))
                            .opacity(1.0 - progress * 1.5)
                            .padding(.trailing, 20)
                    }
                }
                .frame(width: currentSliderWidth, height: knobSize)

            // Draggable knob
            RoundedRectangle(cornerRadius: cornerRadius - 4)
                .fill(Color.white)
                .frame(width: knobSize - 8, height: knobSize - 8)
                .overlay(
                    Image(systemName: isCompleted ? "checkmark" : "chevron.right")
                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                        .font(.system(size: 20, weight: .bold))
                        .animation(.easeInOut(duration: 0.2), value: isCompleted)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                .offset(x: dragOffset + 4)
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            let newOffset = max(0, min(value.translation.width, maxDragDistance))
                            dragOffset = newOffset

                            // Haptic feedback when reaching the end
                            if newOffset >= maxDragDistance - 5 && !isCompleted {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }
                        }
                        .onEnded { value in
                            isDragging = false

                            if !isCompleted && dragOffset >= maxDragDistance * 0.8 {
                                // Activate guard mode
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = maxDragDistance
                                    isCompleted = true
                                }
                                let successFeedback = UINotificationFeedbackGenerator()
                                successFeedback.notificationOccurred(.success)

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    onComplete()
                                    onStateChanged?(true)
                                }
                            } else if isCompleted && dragOffset <= maxDragDistance * 0.2 {
                                //Deactivate guard mode
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = 0
                                    isCompleted = false
                                }

                                let warningFeedback = UINotificationFeedbackGenerator()
                                warningFeedback.notificationOccurred(.warning)
                                onStateChanged?(false)

                            } else {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    dragOffset = isCompleted ? maxDragDistance : 0
                                }
                            }
                        }
                )
            }
            .frame(width: currentSliderWidth, height: knobSize)
            .frame(maxWidth: .infinity)
            .clipped()
            .onAppear {
                if isCompleted {
                    dragOffset = maxDragDistance
                }
            }
        }
        .frame(height: knobSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .contentShape(Rectangle()) //entire area tappable
    }

    private func resetSlider() {
        withAnimation(.easeInOut(duration: 0.5)) {
            dragOffset = 0
            //should stay activated
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        iPhoneSliderView {
            print("Slider completed!")
        }
    }
}
