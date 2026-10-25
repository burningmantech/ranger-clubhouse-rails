# frozen_string_literal: true

module PhotoRejections
  REJECTIONS = {
    'underexposed': {
      label: "Underexposed",
      message: "The photo is not bright enough. Your face should be evenly lit and clearly visible. Try taking the photo outside, or turning on more lights within the room"
    },
    'overexposed': {
      label: "Overexposed",
      message: "The photo is too bright. Try turning down the lighting in the room, or move out of direct sunlight"
    },
    'blurry': {
      label: "Too blurry",
      message: "The photo is blurry. Retake the photo and make sure things are in focus. Don't forget to clean the lens!"
    },
    'grainy': {
      label: "Too grainy",
      message: "The photo is too grainy. Move closer to the camera AND not crop the image OR the photo file is too small."
    },
    'altered': {
      label: "Altered / Photoshopped",
      message: "The photo has been altered. Do not use beauty filters, emojis, copy-n-paste, etc."
    },
    'other-people': {
      label: "Other people present",
      message: "This might not be a photo of just you. Submit a new photo with only you in it."
    },
    'scanned-photo': {
      label: "Scanned photo",
      message: "A scanned photo or a photo of a photo cannot be used. Try using a smartphone or tablet to take a selfie."
    },
    'is-photo-of-id': {
      label: "Driver's License / Photo",
      message: "Pictures of your driver's license, passport, or similar id is not allowed. Submit an original photo."
    },
    'not-color': {
      label: "Not color image",
      message: "A black and white photo cannot be used. Submit a color photo."
    },
    'dark-background': {
      label: "Dark background",
      message: "The background is poorly lit. Retake the photo against a lighter background or one with better lighting."
    },
    'no-profile-background-contrast': {
      label: "No profile/background contrast",
      message: "There is not enough contrast between the background and your profile. Retake the photo with a different background."
    },
    'no-hair-background-contrast': {
      label: "No hair/background contrast",
      message: "There is not enough contrast between your hair and the background. Retake the photo with a different background."
    },
    'shadows': {
      label: "Shadows on face",
      message: "You have one or more shadows on your face. Your face should be evenly lit and clearly visible."
    },
    'wearing-hat': {
      label: "No hats/headbands",
      message: "Remove anything on your head such as hats, headbands, wreaths, horns, flowers, etc. Woven braids and religious attire is okay."
    },
    'wearing-goggles': {
      label: "Wearing sunglasses / goggles",
      message: "Sunglasses and goggles are not allowed. Your entire face and eyes must be clearly visible. Clear prescription glasses are okay as long as we can see your eyes."
    },
    'face-covered': {
      label: "Face covered (masks, paint, etc)",
      message: "Your face is covered. No sunglasses, dust masks, face paint, etc. Your entire face must be clearly visible."
    },
    'not-facing': {
      label: "Not facing camera",
      message: "You must be facing the camera. Side profile shots are not allowed. Turn and face the camera dead on."
    },
    'too-close': {
      label: "Face too close",
      message: "Your face is too close to the camera. Back up a little. Your shoulders should be in the photo."
    },
    'too-far': {
      label: "Too far away",
      message: "Your face is not close enough to the camera. Move in a bit. Your face and shoulders should take up most of the frame."
    },
    'not-centered': {
      label: "Face not centered",
      message: "Your face needs to be front and centered. The entire head needs to be visible, with space between the top of your head and the frame."
    },
    'head-cropped': {
      label: "Head cropped",
      message: "Portions of your head is cropped. Your entire head needs to be visible, with space between the top of your head, sides, chin, and the photo edge."
    },
    'no-margin': {
      label: "No margins",
      message: "You do not have enough space around your face and the edge of the frame. Zoom out or move away from the camera."
    }
  }.with_indifferent_access.freeze
end
